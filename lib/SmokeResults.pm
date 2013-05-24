package SmokeResults;
use Dancer ':syntax';

use 5.014;
use warnings;
use autodie;

use JSON qw/decode_json/;
use Date::Simple qw/date today/;;
use GD;

our $VERSION = '0.1';
my $days_to_show = 14;
my $rect_size    = 15;

my %color = (
    ok      => "#00ff00",
    black   => "#000000",
    test    => "#ff0000",
    build   => "#800000",
    prereq  => "#ffff00",
);

sub filename {
    my $d = shift;
    $d =~ s/-//g;
    return "/home/smoker/smoke-history/results-$d.json";
}

sub get_projects {
    my $report_date = date('2013-05-24');
    my $date = $report_date;
    
    my $days_shown = 0;
    my $projects = {};
    my $dates = [];

    while ($days_shown < $days_to_show) {
        my $fn = filename($date);
        last unless -e $fn;
        push @$dates, $date;
        open my $IN, '<:encoding(UTF-8)', $fn;
        my $raw_json = do { local $/; <$IN> };
        close $IN;
        my %smoke = %{ decode_json($raw_json) };
        while (my ($project, $result) = each %smoke) {
            $projects->{$project}{$date} = $result;
        }
    } continue {
        $days_shown++; $date--
    };
    
    $projects, $dates, $report_date;
}

sub rank {
    my $project = shift;
    my $count = 0 + keys %$project;
    my $days = 0;
    my @sorted_dates = sort { $b cmp $a } keys %$project;
    foreach my $date (@sorted_dates) {
        last if ($project->{$date}{"test"});
        $days++;
    }
    
    if ($days == $count) {
        $days += 1 unless ($project->{$sorted_dates[0]}{"build"});
        $days += 1 unless ($project->{$sorted_dates[0]}{"prereq"});
    }
    
    $days = $count * 2 if ($days == 0);
    
    $days;
}

sub get_projects_report {
    my ($project_hash, $dates, $report_date) = @_;
    
    my $projects = [];
    foreach my $pn (sort { 
                            rank($project_hash->{$a}) <=> rank($project_hash->{$b})
                            || $a cmp $b
                         } keys %$project_hash) {
        my $line = [ "<a href=\"project/$pn\">$pn</a>" ];
        
        for my $date (sort @$dates) {
            my $color = $color{black};
            
            my $res  = $project_hash->{$pn}->{$date};
            if ($res) {
                my $failed = 0;
                for my $state (qw(prereq build test)) {
                    unless ($res->{$state}) {
                        $color = $color{$state};
                        $failed = 1;
                        last;
                    }
                }
                unless ($failed) {
                    $color = $color{ok};
                }
            }
            
            push @$line, $color;
        }

        push $projects, $line;
    }
    
    $projects;
};

sub get_user {
    my $project = shift;
    # open my $in, '-|', "panda info " . $project;
    # while (<$in>) {
    #     if (/\"Source-url\"\s+\=\>\s+\"(.*)\"/) {
    #         my $url = $1;
    #         if ($url =~ m[github.com/(.*?)/]) {
    #             $in->close();
    #             return $1;
    #         }
    #     }
    # }
    # 
    # $in->close();
    
    if ($project eq "Math::Vector") {
        return "colomon";
    }
    
    "unknown";
}

sub grep_by_user {
    my $full_projects = shift;
    my $user = shift;
    
    my $grepped_projects = {};
    
    foreach my $pn (keys %$full_projects) {
        my $pn_user = get_user($pn);
        $grepped_projects->{$pn} = $full_projects->{$pn} if ($pn_user eq $user);
    }

    $grepped_projects;
}


get '/' => sub {
    template 'index';
};

get '/report' => sub {
    my ($project_hash, $dates, $report_date) = get_projects();
    my $projects = get_projects_report($project_hash, $dates, $report_date);
    template 'report' => { days_to_show => $days_to_show,
                           projects => $projects };
};

get '/report/:user' => sub {
    my ($project_hash, $dates, $report_date) = get_projects();
    $project_hash = grep_by_user($project_hash, param('user'));
    my $projects = get_projects_report($project_hash, $dates, $report_date);
    template 'report' => { days_to_show => $days_to_show,
                           projects => $projects };
};

get '/project/:name' => sub {
    open my $in, '-|', "panda info " . param('name');
    my $lines = [];
    while (<$in>) {
        if (/\"(.*)\"\s+\=\>\s+\"(.*)\"/) {
            my $data_name = $1;
            my $data = $2;
            if ($data =~ m/git:(.*).git/) {
                $data = "<a href=\"http:$1\"> $data </a>";
            }
            push @$lines, [ $data_name, $data ];
        }
    }
    $in->close;
    
    my ($project_hash, $dates, $report_date) = get_projects();
    my $project = $project_hash->{param('name')};
    
    my $runs = [];
    foreach my $date (sort { $b cmp $a } keys %$project) {
        my $line = [$date];
        my %res = %{$project->{$date}};
        for my $stage (qw(prereq build test)) {
            if (defined $res{$stage}) {
                if ($res{$stage} == 1) {
                    push @$line, '<div class="implemented">+</div>';
                } else {
                    push @$line, '<div class="missing">-</div>';
                }
            } else {
                push @$line, '<div class="unknown">?</div>';
            }
        }
        push @$line, $res{description} // '';

        push @$runs, $line;
    }

    template 'project' => { info => $lines,
                            runs => $runs };
};

get '/hello/:name' => sub {
    # do something
 
    return "Hello ".param('name');
};

true;
