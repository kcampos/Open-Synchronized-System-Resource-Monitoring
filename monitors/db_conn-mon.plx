#!/usr/bin/env perl
# monitor db connections
# Usage: db_conn-mon.plx <stat interval in seconds> <num of stat reqs> <SYS_USER>, <SYS_PASS>, <schema> [, <schema>]

my $interval = shift;
my $num_attempts = shift;
my $user = shift;
my $pass = shift;
my @schemas = @ARGV;

my ($i, $out, $schema);

my $where_snippet = "s.username = '" . (shift @schemas) . "'";
while($schema = shift @schemas)
{
	$where_snippet .= " or s.username = '$schema'"
}

for ($i=1;$i<=$num_attempts;$i++)
{
	$out = `sqlplus -s /nolog <<EOF
	connect $user/$pass as SYSDBA
	select s.username, s.machine, count(*) from v\\\$session s where ($where_snippet) group by s.machine, s.username order by 1;
	exit
	EOF`;

	my $time = `date +%r`;
	print "$time\n";
	print "$out\n";
		
	print 'END';
	print '-' x 40;
	print "\n";
	
	sleep $interval;
}

0;
