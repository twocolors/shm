#!/usr/bin/perl

# https://yoomoney.ru/transfer/myservices/http-notification

use v5.14;

use Digest::SHA qw(sha1_hex);
use SHM qw(:all);
my $user = SHM->new( skip_check_auth => 1 );

our %vars = parse_args();

my $config = get_service('config', _id => 'pay_systems');

unless ( $config ) {
    print_json( { status => 400, msg => 'Error: config pay_systems->yoomoney->secret not exists' } );
    exit 0;
}

my $secret = $config->get_data->{yoomoney}->{secret};

my $digest = sha1_hex( join('&',
	@vars{ qw/notification_type operation_id amount currency datetime sender codepro/ },
	$secret,
	$vars{label},
));

if ( $digest ne $vars{sha1_hash} ) {
    print_json( { status => 400 } );
    exit 0;
}

if ( $vars{test_notification} ) {
    $user->payment(
        user_id => 1,
        money => 0,
        pay_system_id => 'yoomoney-test',
        comment => \%vars,
    );
    $user->commit;
    print_json( { status => 200,  msg => 'Test OK' } );
    exit 0;
}

my $date = time;
my ( $user_id, $amount ) = @vars{ qw/label withdraw_amount/ };

unless ( $user_id ) {
    print_json( { status => 400, msg => 'User (label) required' } );
    exit 0;
}

unless ( $user = $user->id( $user_id ) ) {
    print_json( { status => 404, msg => "User [$user_id] not found" } );
    exit 0;
}

unless ( $user->lock( timeout => 10 )) {
    print_json( { status => 408, msg => "The service is locked. Try again later" } );
    exit 0;
}

$user->payment(
    user_id => $user_id,
    money => $amount,
    pay_system_id => 'yoomoney',
    comment => \%vars,
);

$user->commit;

print_json( { status => 200, msg => "Payment successful" } );

exit 0;

