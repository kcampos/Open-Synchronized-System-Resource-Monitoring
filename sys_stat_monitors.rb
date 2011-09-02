#!/usr/bin/env ruby

require 'optparse'
require 'yaml'

# Initialize
@options = {}
@config = {}
errors = [] # Gather arg validation errors

# Get cmd line options
optparse = OptionParser.new do |opts|
  
  # Banner
  opts.banner = "Usage: sys_stat_monitors.rb [OPTIONS]"
  
  # Definition of options
  opts.on('-h', '--help', 'Display help screen') do
    puts opts
    exit
  end
  
  # Config file
  @options[:config_file] = nil
  opts.on('-c', '--config FILE', 'path to yaml config file') do |file|
    @options[:config_file] = file
    errors.push("#{file} does not exist") unless(File.file?(@options[:config_file]))
    errors.push("#{file} does not appear to be a yaml file, must end in .yaml") unless(file =~ /\.yaml$/)
  end
  
  # Log file
  @options[:log] = nil
  opts.on('-l', '--log FILE', 'path to log output') do |file|
    @options[:log] = file
  end

  # Enable debug
  @options[:debug] = false
  opts.on('-d', '--debug', 'enable debug logging') do
    @options[:debug] = true
  end
  
  # Path to monitor commands on remote hosts, must end with '/'
  @options[:cmd_path] = '~/bin/'
  opts.on('-p', '--path', 'path to monitoring commands') do |path|
    @options[:cmd_path] = path
  end
  
end

optparse.parse!
errors.push("Must specify config file") if(@options[:config_file].nil?)
@options[:log] = (@options[:log].nil? ? "#{Time.now.to_i}.log" : @options[:log])

(errors.each { |err| puts err } and exit) if(!errors.empty?)


# METHODS

# Start log, return File obj
def start_log(log)
  File.open(log, 'w')
end

# Print messages to log and stdout
def info_msg(msg)
  @log.puts(msg)
  puts msg
end

# Print debug messages to log and stdout if specified
def debug_msg(msg)
  if(@options[:debug])
    @log.puts(msg)
    puts msg
  end
end

# Parse the passed in config file
def parse_config(config)
  @config = YAML.load_file(config)
  debug_msg("CONFIG: #{@config.inspect}")
end


# run_cmd
def run_remote_cmd(user, host, cmd, cmd_log, cmd_path=@options[:cmd_path], forked=true)
  debug_msg("exec: run_remote_cmd(#{user}, #{host}, #{cmd}, #{cmd_log}, #{forked})")
  forked ? fork { `ssh #{user}@#{host} "#{cmd_path}#{cmd}" > #{cmd_log}` } : `ssh #{user}@#{host} "#{cmd_path}#{cmd}" > #{cmd_log}`
end


# Start monitors
def start_monitors
  p = {}
  p[:host] = {}
  
  # Per host
  i = 1
  @config[:hosts].each_key do |host|
    
    debug_msg("Working with host [#{host}]")
    
    p[:host][host] = {} 
    p[:host][host][:phase] = {}
    p[:host][host][:fpid] = fork do
      
      debug_msg("#{i}> p in: #{p.inspect}")
      debug_msg("#{i}> In host [#{host}] fpid fork, pid [#{p[:host][host].inspect}]")
      
      @config[:hosts][host][:phases].each_key do |phase|

        debug_msg("Working with phase [#{phase}]")

        p[:host][host][:phase][phase] = {}
        p[:host][host][:phase][phase][:pids] = {}
        p[:host][host][:phase][phase][:fpid] = fork do # start phase fork

          @config[:hosts][host][:pids].split(',').each do |pid|

            debug_msg("Working with pid [#{pid}]")
            p[:host][host][:phase][phase][:pids][pid] = {}
            p[:host][host][:phase][phase][:pids][pid][:fpid] = fork do

              info_msg("Launching phase #{phase} monitors on #{host} for pid #{pid}... (#{Time.now.to_s})")

              # Forked memory cmd
              p[:host][host][:phase][phase][:pids][pid][:mem] = run_remote_cmd(@config[:hosts][host][:user], host, 
                "mem-stat.plx #{pid} #{@config[:hosts][host][:phases][phase][:interval]} #{@config[:hosts][host][:phases][phase][:amount]}",
                "#{@config[:base_log_name]}-#{host}-phase#{phase}-mem_stats.log"
              )

              # Don't wait
              debug_msg("Forked mem cmd pid return: [#{p[:host][host][:phase][phase][:pids][pid][:mem]}]")
              Process.detach(p[:host][host][:phase][phase][:pids][pid][:mem])

              # Forked net cmd
              p[:host][host][:phase][phase][:pids][pid][:net] = run_remote_cmd(@config[:hosts][host][:user], host, 
                "net-mon.plx #{@config[:hosts][host][:phases][phase][:interval]} #{@config[:hosts][host][:phases][phase][:amount]} #{@config[:hosts][host][:http_port]}",
                "#{@config[:base_log_name]}-#{host}-phase#{phase}-net_mon.log"
              )

              # Don't wait
              debug_msg("Forked net cmd pid return: [#{p[:host][host][:phase][phase][:pids][pid][:net]}]")
              Process.detach(p[:host][host][:phase][phase][:pids][pid][:net])

              # Forked cpu cmd
              p[:host][host][:phase][phase][:pids][pid][:cpu] = run_remote_cmd(@config[:hosts][host][:user], host, 
                "sar -u -x #{pid} #{@config[:hosts][host][:phases][phase][:interval]} #{@config[:hosts][host][:phases][phase][:amount]}",
                "#{@config[:base_log_name]}-#{host}-phase#{phase}-cpu_stats.log", nil
              )

              # WAIT
              debug_msg("Forked cpu cmd pid return: [#{p[:host][host][:phase][phase][:pids][pid][:cpu]}]")
              info_msg("Waiting for monitors for phase #{phase} on #{host} to stop...")
              Process.waitpid(p[:host][host][:phase][phase][:pids][pid][:cpu])
              info_msg("...Monitors for phase #{phase} on #{host} stopped (#{Time.now.to_s})")

            end #end pids fork

          end #end pids

          # Wait for commands in phase
          p[:host][host][:phase][phase][:pids].each_key { |pid| Process.waitpid(p[:host][host][:phase][phase][:pids][pid][:fpid]) }

        end #end phase fork

        # Wait for phase to complete before launching next phase
        Process.waitpid(p[:host][host][:phase][phase][:fpid])

      end #end phase
    
    end #end host fork
    debug_msg("#{i}> p out: #{p.inspect}")
    i+=1
  end #end host
  
  # wait for each host to come back
  @config[:hosts].each_key { |host| Process.waitpid(p[:host][host][:fpid]) }
  
end


# MAIN

@log = start_log(@options[:log])
debug_msg("OPTIONS: #{@options.inspect}")

parse_config(@options[:config_file])

start_monitors

exit 0





