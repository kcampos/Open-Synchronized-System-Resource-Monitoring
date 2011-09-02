#!/usr/bin/env perl
# monitor network connections
# Usage: net-mon.plx <stat interval in seconds> <num of stat reqs> <port numbers comma sep - opt>

my ($interval, $num_attempts, $port) = @ARGV;
my @ports = split(/,/, $port);

my ($i, $out);
my $cmd = 'netstat -tn | grep tcp';
if(scalar(@ports))
{
	my $port_search = join('|\:', @ports);
	$cmd = $cmd . " | egrep -e '\\:$port_search'";
}

$cmd = $cmd . " | awk '{ print \$6 }'";
print "Cmd: $cmd\n";

for ($i=1;$i<=$num_attempts;$i++)
{
	$out = `$cmd`;
	my %report;
	
	@statuses = split(/\n/, $out);
	foreach my $status (@statuses)
	{
		$report{$status} += 1;
	}
	
	my $time = `date +%r`;
	print "$time\n";
	
	foreach my $status (keys %report)
	{
		print "$status: $report{$status}\n";
	}
	
	print '-' x 20;
	print "\n";
	
	sleep $interval;
}

0;
