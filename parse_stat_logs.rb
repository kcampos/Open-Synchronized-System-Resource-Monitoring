#!/usr/bin/env ruby

require 'optparse'


# Initialize
options = {}
options[:debug] = false
config = {}
errors = [] # Gather arg validation errors

# Get cmd line options
optparse = OptionParser.new do |opts|
  
  # Banner
  opts.banner = "Usage: parse_stat_logs.rb [OPTIONS]"
  
  # Definition of options
  opts.on('-h', '--help', 'Display help screen') do
    puts opts
    exit
  end
  
  # CPU file
  #opts.on('-c', '--cpu FILE', 'path to cpu stat file') do |file|
  #  options[:cpu_file] = file
  #  errors.push("#{file} does not exist") unless(File.file?(options[:cpu_file]))
  #end
  
  # Mem file
  #opts.on('-m', '--mem FILE', 'path to mem stat file') do |file|
  #  options[:mem_file] = file
  #  errors.push("#{file} does not exist") unless(File.file?(options[:mem_file]))
  #end
  
  # Net file
  opts.on('-n', '--net FILE', 'path to net stat file') do |file|
    options[:net_file] = file
    errors.push("#{file} does not exist") unless(File.file?(options[:net_file]))
  end
  
  # DB file
  opts.on('-d', '--db FILE', 'path to db stat file') do |file|
    options[:db_file] = file
    errors.push("#{file} does not exist") unless(File.file?(options[:db_file]))
  end
    
end

optparse.parse!
(errors.each { |err| puts err } and exit) if(!errors.empty?)

#puts "Options: #{options.inspect}"

# Net stat data
class NetStat
  
  attr_reader :values, :max, :min, :average
  
  def initialize(file)
    connection_str = `grep 'ESTABLISHED' #{file} | awk '{print $2}'`
    @values = connection_str.split.collect{ |x| x.to_i }.sort
  end
  
  def max
    @values.last
  end
  
  def min
    @values.first
  end
  
  def average
    total = 0
    @values.each { |val| total += val }
    total/@values.size
  end
  
  def median
    @values[(@values.size / 2)]
  end
  
  def to_s
    puts "Net Statistics"
    puts "---------------"
    puts "Min: [#{self.min}]\tMax: [#{self.max}]\tAvg: [#{self.average}]\tMed: [#{self.median}]"
    puts "------------------------------------------------------------"
  end
  
end


# DB session data
class DbSessionStat
  
  attr_reader :data, :col_data
  
  def initialize(file)
    #@file = file
    @data = parse_db_stat_file(file)
    @col_data = collect_data
  end
  
  def max(opts={})
    
    defaults = {
      :schema => 'all',
      :machine => 'all',
      :print => false
    }
    
    opts = defaults.merge(opts)
    
    max_sessions = {}
    
    # Collect max values into hash
    self.col_data.each_key do |schema|
      if(opts[:schema] == 'all' or opts[:schema] == schema)
        max_sessions[schema] = {} if(!max_sessions[schema])
        
        self.col_data[schema].each_key do |machine|
          if(opts[:machine] == 'all' or opts[:machine] == machine)
            max_sessions[schema][machine] = self.col_data[schema][machine].collect{ |x| x.to_i }.sort.last
          end
        end
      end  
    end
    
    # Print if requested
    if(opts[:print])
      max_sessions.each_key do |schema|
        puts "Schema: #{schema}"
        max_sessions[schema].each_pair do |machine, max_sesh|
          puts "\t#{machine}: #{max_sesh} (Max)"
        end
      end
    end
    
  end
  
  def min
    
  end
  
  def average
    
  end
  
  # Options as far as what data to print
  def to_s(opts={})
    
    defaults = {
      :max => true,
      :min => false,
      :average => false,
      :verbose => false
    }
    opts = defaults.merge(opts)
    
    puts "DB Connection Statistics"
    puts "-------------------------"
    
    # Print max values
    self.max({:print => true}) if(opts[:max])
      
    # Print all the stats
    if(opts[:verbose])
      self.data.each_key do |interval|
        print "Interval: #{interval}, "
      
        self.data[interval].each_key do |timestamp|
          puts timestamp
        
          self.data[interval][timestamp].each_key do |schema|
            puts "\tSchema: #{schema}"
          
            self.data[interval][timestamp][schema].each_pair do |machine, sessions|
              puts "\t\tHost: #{machine}"
              puts "\t\tSessions: #{sessions}"
            end
          end
        end
      end
    end
    
    puts "------------------------------------------------------------"
    
  end
  
  private
  
  def parse_db_stat_file(file)
    fh = File.open(file)
    data = {}
    interval = 0
    
    # Iterate over file
    while(line = fh.gets)
      
      # Find start of section - timestamp
      if(line =~ /^(\d{2}:\d{2}:\d{2}.+)/)
        timestamp = $1
        interval += 1
        data[interval] = {}
        data[interval][timestamp] = {}
                
        # Ingest all the data for this section
        until(cur_line = fh.gets and cur_line =~ /^END/)
          
          if(cur_line !~ /^(USERNAME|-|MACHINE)/ and cur_line =~ /^\w/)
            # Line is not a SQL header and it's not blank
            
            # Looking for schema
            if(cur_line =~ /^(\w+)$/)
              schema = $1
              data[interval][timestamp][schema] = {} if(!data[interval][timestamp][schema])
              
              # Now get the next line that has the machine and session count
              next_line = fh.gets
              if(next_line =~ /^([^\s]+)\s+(\d+)$/)
                machine = $1
                sessions = $2
                
                data[interval][timestamp][schema][machine] = sessions
              end
              
            end
              
          end
          
        end
        
      end
      
    end
    
    
    # Gather session data into schema/machine hash collection
    def collect_data
      col_sessions = {}
      
      # Populate 
      self.data.each_key do |interval|
        self.data[interval].each_key do |timestamp|
          self.data[interval][timestamp].each_key do |schema|
            col_sessions[schema] = {} if(!col_sessions[schema])
            self.data[interval][timestamp][schema].each_pair do |machine, sessions|
              col_sessions[schema][machine] = [] if(!col_sessions[schema][machine])
              col_sessions[schema][machine] << sessions
            end
          end
        end
      end
      
      return col_sessions
      
    end
    
    return data
    
  end
  
end



# MAIN
if(options[:net_file])
  net = NetStat.new(options[:net_file])
  net.to_s
end

if(options[:db_file])
  db = DbSessionStat.new(options[:db_file])
  db.to_s
end

