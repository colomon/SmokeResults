package SmokeResults;
use Dancer ':syntax';

use utf8;
use 5.014;
use warnings;
use autodie;

use JSON qw/decode_json/;
use Date::Simple qw/date today/;;
use LWP::Simple ();
use Encode qw(decode_utf8);
use GD;

our $VERSION = '0.1';
my $days_to_show = 14;
my $rect_size    = 15;
my $path = $ENV{SMOKE_HISTORY_PATH} // "$ENV{HOME}/smoke-history";

my %color = (
    ok       => '<div class="smfok">✓</div>',
    black    => '<div class="smfmissing">?</div>',
    test     => '<div class="smftest">T</div>',
    build    => '<div class="smfbuild">B</div>',
    prereq   => '<div class="smfprereq">P</div>',
    warnings => '<div class="smfwarn">W</div>',
);

my %explanation = (
    ok       => 'Passes all tests',
    black    => 'No info available',
    test     => 'Tests fail',
    build    => 'Build fails',
    prereq   => 'Prerequisites failing',
    warnings => 'Build/tests had warnings',
);

sub get_all_dates {
    my $dates = [];
    opendir(DIR, $path) or die "can't opendir $path: $!";
    while (defined(my $file = readdir(DIR))) {
        if ($file =~ /results-(\d+).json/) {
            push @$dates, $1;
        }
    }
    closedir(DIR);
    $dates;
}

sub filename {
    my $d = shift;
    $d =~ s/-//g;
    return $path . "/results-$d.json";
}

sub pretty_date {
    my $date = shift;
    if ($date =~ /(\d\d\d\d)(\d\d)(\d\d)/) {
        $date = "$1-$2-$3";
    }
    $date
}

sub get_projects {
    my $dates_list = get_all_dates();
    my @dates = (reverse sort @$dates_list)[0 .. $days_to_show - 1];
    # my $report_date = date('2013-05-24');
    # my $date = $report_date;
    
    my $days_shown = 0;
    my $projects = {};
    my $dates = [];

    foreach my $date (@dates) {
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
        $days_shown++;
    }
    
    my @short_dates;
    foreach my $date (@$dates) {
        if ($date =~ /\d\d\d\d\d\d(\d\d)/) {
            push @short_dates, $1;
        }
    }
    
    my $short_dates = [ reverse @short_dates ];
    
    
    $projects, $dates, $dates[0], pretty_date($dates[-1 + @$dates]), pretty_date($dates[0]), $short_dates;
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

    my $project_to_author = get_author_hash();

    my $projects = [];
    my %count;
    foreach my $pn (sort { 
                            rank($project_hash->{$a}) <=> rank($project_hash->{$b})
                            || $a cmp $b
                         } keys %$project_hash) {
        my $author = $project_to_author->{$pn} // "Unknown";
        my $line = [ 
            "<a href=\"/project/$pn\">$pn</a>", 
            "<a href=\"report/$author\">$author</a>"
        ];
        
        for my $date (sort @$dates) {
            my $color = $color{black};
            
            my $res  = $project_hash->{$pn}->{$date};
            if ($res) {
                my $failed = 0;
                for my $state (qw(prereq build test)) {
                    unless ($res->{$state}) {
                        $color = $color{$state};
                        $count{$date}{$state}++;
                        $failed = 1;
                        last;
                    }
                }
                unless ($failed) {
                    $color = $color{ok};
                    $count{$date}{ok}++;
                }
            }
            
            $count{$date}{black}++ if ($color eq $color{black});
            push @$line, $color;
        }

        # # very hacky way of getting stats on just the most recent day
        # {
        #     my $date = $dates->[0];
        #     my $color = $color{black};
        #     
        #     my $res  = $project_hash->{$pn}->{$date};
        #     if ($res) {
        #         my $failed = 0;
        #         for my $state (qw(prereq build test)) {
        #             unless ($res->{$state}) {
        #                 $color = $color{$state};
        #                 $count{$state}++;
        #                 $failed = 1;
        #                 last;
        #             }
        #         }
        #         unless ($failed) {
        #             $color = $color{ok};
        #             $count{ok}++;
        #         }
        #     }
        #     $count{black}++ if ($color eq $color{black});
        # }
        # 

        push @$projects, $line;
    }
    
    my $key = [];
    foreach my $k ("ok", "test", "build", "prereq", "black") {
        push @$key, [ 
            $color{$k}, 
            $explanation{$k}, 
            $count{$dates->[-1]}{$k} // 0, 
            $count{$dates->[0]}{$k} // 0 
        ];
    }
    
    $projects, $key;
};

sub get_author_hash {
    open my $in, '<', $path . "/authors";
    my $project_to_author;
    while (<$in>) {
        if (/\"(.*)\"\s+\=\>\s+\"(.*)\"/) {
            $project_to_author->{$1} = $2;
        }
    }
    $in->close;
    
    $project_to_author;
}

sub grep_by_user {
    my $full_projects = shift;
    my $user = shift;
    
    my $project_to_author = get_author_hash();
    
    my $grepped_projects = {};
    
    foreach my $pn (keys %$full_projects) {
        my $pn_user = $project_to_author->{$pn} // "unknown";
        $grepped_projects->{$pn} = $full_projects->{$pn} if ($pn_user eq $user);
    }

    $grepped_projects;
}

get '/' => sub {
    redirect '/report';
};

get '/report' => sub {
    my ($project_hash, $dates, $report_date, $first_date, $last_date, $short_dates) = get_projects();
    my ($projects, $key) = get_projects_report($project_hash, $dates, $report_date);
    template 'report' => { days_to_show_plus_one => $days_to_show + 1,
                           projects => $projects,
                           dates => $short_dates,
                           first_date => $first_date,
                           last_date => $last_date,
                           key => $key };
};

get '/report/:user' => sub {
    my ($project_hash, $dates, $report_date, $first_date, $last_date, $short_dates) = get_projects();
    $project_hash = grep_by_user($project_hash, param('user'));
    my ($projects, $key) = get_projects_report($project_hash, $dates, $report_date);
    template 'report' => { days_to_show_plus_one => $days_to_show + 1,
                           projects => $projects,
                           dates => $short_dates,
                           first_date => $first_date,
                           last_date => $last_date,
                           key => $key,
                           author => param('user') };
};

get '/project/:name' => sub {
    my $name = param('name');
    my $info_str = LWP::Simple::get("http://ecosystem-api.p6c.org/module/$name");
    my $info = eval {
        decode_json decode_utf8 $info_str;
    };
    # warn $@ if $@;

    my @lines;
    if ($info) {
        for my $key (qw(author description)) {
            if (my $value = $info->{$key}) {
                push @lines, [ $key => $value ];
            }
        }
        if (my $source_url = $info->{'source-url'}) {
            if ($source_url =~ m/git:(.*).git/) {
                push @lines, [ 'source-url' => "<a href=\"https:$1\"> $source_url </a>" ];
            }
        }
    }

    
    my ($project_hash, $dates, $report_date) = get_projects();
    my $project = $project_hash->{param('name')};
    
    my $runs = [];
    foreach my $date (sort { $b cmp $a } keys %$project) {
        my $line = [ pretty_date($date) ];
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

    template 'project' => { info => \@lines,
                            runs => $runs };
};

get '/hello/:name' => sub {
    # do something
 
    return "Hello ".param('name');
};

true;
