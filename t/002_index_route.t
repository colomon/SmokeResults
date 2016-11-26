use strict;
use warnings;

use Test::More tests => 3;

# the order is important
use SmokeResults;
use Dancer::Test;

route_exists [GET => '/'], 'a route handler is defined for /';
response_redirect_location_is [GET => '/'], 'http://localhost/report';
response_status_is ['GET' => '/report'], 200, 'response status is 200 for /report';
