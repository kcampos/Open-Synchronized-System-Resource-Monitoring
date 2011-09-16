#!/usr/bin/env ruby

# Must use Ruby 1.9.2+

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
  debug_msg("exec: run_remote_cmd(#{user}, #{host}, #{cmd}, #{cmd_log}, #{cmd_path}, #{forked})")
  forked ? fork { `ssh #{user}@#{host} "#{cmd_path}#{cmd}" > #{cmd_log}` } : `ssh #{user}@#{host} "#{cmd_path}#{cmd}" > #{cmd_log}`
end


# Figure out which pids we can detach and which we can wait on
# This may be useless and we may be able to just wait on all pids. no harm no foul
def do_wait(pid_times)
  
  debug_msg("in pid_times: #{pid_times.inspect}")
  highest_waits = pid_times.select { |k,v| v == pid_times.values.max } # has for highest pid wait times
  debug_msg("highest_waits: #{highest_waits.inspect}")
  pid_times.reject! { |k,v| v == highest_waits.values.max } # removes those pids from the hash
  debug_msg("out  pid_times: #{pid_times.inspect}")
  
  # Don't wait for these pids
  pid_times.each_pair do |pid, total_time|
    debug_msg("Detaching pid: #{pid}")
    Process.detach(pid)
  end
  
  # Wait for whatever the longest pid wait time is
  highest_waits.each_pair do |pid, total_time|
    debug_msg("Waiting for pid: #{pid}")
    Process.waitpid(pid)
  end
  
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
            p[:host][host][:phase][phase][:pids][pid][:total_time] = {}
            p[:host][host][:phase][phase][:pids][pid][:fpid] = fork do

              info_msg("Launching phase #{phase} monitors on #{host} for pid #{pid}... (#{Time.now.to_s})")

              if(@config[:hosts][host][:phases][phase][:mem])
                # Fork memory command
                mem_cmd = (pid == 'ALL' ? "sar -r #{@config[:hosts][host][:phases][phase][:mem][:interval]} #{@config[:hosts][host][:phases][phase][:mem][:amount]}" :
                                          "mem-stat.plx #{pid} #{@config[:hosts][host][:phases][phase][:mem][:interval]} #{@config[:hosts][host][:phases][phase][:mem][:amount]}")
                
                p[:host][host][:phase][phase][:pids][pid][:mem] = run_remote_cmd(@config[:hosts][host][:user], host, mem_cmd,
                  "#{@config[:base_log_name]}-#{host}-phase#{phase}-mem_stats.log"
                )
                
                debug_msg("#{host}: Forked mem cmd pid return: [#{p[:host][host][:phase][phase][:pids][pid][:mem]}]")
                # Store total mem monitoring time
                p[:host][host][:phase][phase][:pids][pid][:total_time][p[:host][host][:phase][phase][:pids][pid][:mem]] = @config[:hosts][host][:phases][phase][:mem][:interval].to_i * @config[:hosts][host][:phases][phase][:mem][:amount].to_i
              end

              if(@config[:hosts][host][:phases][phase][:net])
                # Forked net cmd
                p[:host][host][:phase][phase][:pids][pid][:net] = run_remote_cmd(@config[:hosts][host][:user], host, 
                  "net-mon.plx #{@config[:hosts][host][:phases][phase][:net][:interval]} #{@config[:hosts][host][:phases][phase][:net][:amount]} #{@config[:hosts][host][:http_port]}",
                  "#{@config[:base_log_name]}-#{host}-phase#{phase}-net_mon.log"
                )
                
                debug_msg("#{host}: Forked net cmd pid return: [#{p[:host][host][:phase][phase][:pids][pid][:net]}]")
                # Store total net monitoring time
                p[:host][host][:phase][phase][:pids][pid][:total_time][p[:host][host][:phase][phase][:pids][pid][:net]] = @config[:hosts][host][:phases][phase][:net][:interval].to_i * @config[:hosts][host][:phases][phase][:net][:amount].to_i
              end
              
              if(@config[:hosts][host][:phases][phase][:cpu])
                # Forked cpu cmd
                cpu_cmd = (pid == 'ALL' ? "sar -u #{@config[:hosts][host][:phases][phase][:cpu][:interval]} #{@config[:hosts][host][:phases][phase][:cpu][:amount]}" :
                                          "sar -u -x #{pid} #{@config[:hosts][host][:phases][phase][:cpu][:interval]} #{@config[:hosts][host][:phases][phase][:cpu][:amount]}")
                                          
                p[:host][host][:phase][phase][:pids][pid][:cpu] = run_remote_cmd(@config[:hosts][host][:user], host, cpu_cmd,
                  "#{@config[:base_log_name]}-#{host}-phase#{phase}-cpu_stats.log", nil
                )
                
                debug_msg("#{host}: Forked cpu cmd pid return: [#{p[:host][host][:phase][phase][:pids][pid][:cpu]}]")
                # Store total cpu monitoring time
                p[:host][host][:phase][phase][:pids][pid][:total_time][p[:host][host][:phase][phase][:pids][pid][:cpu]] = @config[:hosts][host][:phases][phase][:cpu][:interval].to_i * @config[:hosts][host][:phases][phase][:cpu][:amount].to_i
              end
              
              # WAIT
              info_msg("Waiting for monitors for phase #{phase} on #{host} to stop...")
              do_wait(p[:host][host][:phase][phase][:pids][pid][:total_time])
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





