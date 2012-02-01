#!/usr/bin/env perl
# monitor memory usage of particular pids
# Usage: mem-stat.plx <pids comma separated> <stat interval in seconds> <num of stat reqs>

sub getAverage
{
	my @arr = @_;
	my $total = 0;
	my $size = @arr;
	
	foreach $val (@arr)
	{
		$total += $val;
	}
	
	return($total/$size);
}

my ($pidin, $interval, $num_attempts) = @ARGV;
$interval = ($interval ? $interval : 0);
$num_attempts = ($num_attempts ? $num_attempts : 1);
print "PID_IN: [$pidin]\nInterval: [$interval]\nNum_attempts: [$num_attempts]\n";
my @pids = split(/,/, $pidin);
my %pid_mem = ();
my $i;

for ($i=1;$i<=$num_attempts;$i++)
{	
	
	foreach $pid (@pids)
	{
		# Collect pid mem data and any child process mem data
		my $cmd = "ps -o rss,vsize -p $pid --ppid $pid -ww --no-headers ";
		my @out = `$cmd`;
		my ($rss, $vsz) = 0;
		my $iter = 1;
		foreach my $line (@out)
		{
			chomp $line;
			$line =~ s/^\s+//;
			my ($tmp_rss, $tmp_vsz) = split(/ /, $line);
			$rss += $tmp_rss;
			$vsz += ($iter == 1 ? $tmp_vsz : 0); # Only capture parent VSZ value
			$iter++;
		}
		
		#print "PID: [$pid] RSS: [$rss] VSZ: [$vsz]\n";
		push(@{$pid_mem{$pid}{'rss'}}, $rss);
		push(@{$pid_mem{$pid}{'vsz'}}, $vsz);
	}
	
	sleep $interval;
}

print "Totals(kb):\n";
printf '%6s %10s %10s %10s %10s %10s %10s %10s %10s %10s %10s', 'PID', 'RSS Bgn', 'RSS End', 'RSS Grwt', 
	'RSS Avg', 'RSS Med', 'VSZ Bgn', 'VSZ End', 'VSZ Grwt', 'VSZ Avg', 'VSZ Med';
print "\n";
print '-' x 120;
print "\n";

while ( my ($key, $value) = each(%pid_mem))
{
	my $rss_avg   = getAverage(@{$pid_mem{$key}{'rss'}});
	my $rss_med   = @{$pid_mem{$key}{'rss'}}[(scalar(@{$pid_mem{$key}{'rss'}})/2)];
	my $rss_begin = shift @{$pid_mem{$key}{'rss'}};
	my $rss_end   = ($num_attempts > 1 ? pop @{$pid_mem{$key}{'rss'}} : $rss_begin);
	my $rss_growth = $rss_end - $rss_begin;
	my $vsz_avg   = getAverage(@{$pid_mem{$key}{'vsz'}});
	my $vsz_med   = @{$pid_mem{$key}{'vsz'}}[(scalar(@{$pid_mem{$key}{'vsz'}})/2)];
	my $vsz_begin = shift @{$pid_mem{$key}{'vsz'}};
	my $vsz_end   = ($num_attempts > 1 ? pop @{$pid_mem{$key}{'vsz'}} : $vsz_begin);
	my $vsz_growth = $vsz_end - $vsz_begin;
	
	printf '%6s %10d %10d %10d %10d %10d %10d %10d %10d %10d %10d', $key, $rss_begin, $rss_end, $rss_growth, 
		$rss_avg, $rss_med, $vsz_begin, $vsz_end, $vsz_growth, $vsz_avg, $vsz_med;
	print "\n";
}

0;
