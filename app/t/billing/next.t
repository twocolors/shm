use v5.14;

use Test::More;
use Test::MockTime;
use Test::Deep;
use Core::Billing;
use POSIX qw(tzset);

$ENV{SHM_TEST} = 1;

use Core::System::ServiceManager qw( get_service );
use Core::Utils qw(now);
use SHM;
my $user = SHM->new( user_id => 40092 );

$ENV{TZ} = 'Europe/London'; #UTC+0
tzset;

my $next_service = get_service('service')->add(
    name => 'next service',
    cost => '100',
    period_cost => 1,
    category => 'test',
    no_discount => 1,
);

my $test_service = get_service('service')->add(
    name => 'test service',
    cost => '0',
    period_cost => '0.01',
    category => 'test',
    no_discount => 1,
    next => $next_service->id,
);

Test::MockTime::set_fixed_time('2019-04-01T00:00:00Z');
my $start_balance = $user->get->{balance};
my $us = create_service( service_id => $test_service->id );

is( $us->get_expire, '2019-04-02 00:59:59');
is( $us->get_next, $next_service->id );

subtest 'create test service with next' => sub {
    my $wd = $us->withdraw;
    cmp_deeply( scalar $wd->get,
        {
              'user_id' => 40092,
              'months' => 0.01,
              'qnt' => 1,
              'bonus' => '0',
              'discount' => 0,
              'cost' => '0',
              'total' => 0,
              'create_date' => '2019-04-01 01:00:00',
              'withdraw_date' => '2019-04-01 01:00:00',
              'end_date' => '2019-04-02 00:59:59',
              'user_service_id' => $us->id,
              'service_id' => $test_service->id,
              'withdraw_id' => $wd->id,
          }
    , 'Check withdraw');

    my $balance_after_create = $user->get->{balance};
    is ( $balance_after_create, $start_balance, 'Check balance after create');
};

subtest 'check switch test service to next' => sub {
    Test::MockTime::set_fixed_time('2019-04-03T00:00:00Z');

    my $start_balance = $user->get->{balance};

    $us->touch();
    is( $us->get_expire, '2019-05-02 01:49:57');

    my $wd = $us->withdraw;
    cmp_deeply( scalar $wd->get,
        {
              'user_id' => 40092,
              'months' => 1,
              'qnt' => 1,
              'bonus' => '0',
              'discount' => 0,
              'cost' => 100,
              'total' => 100,
              'create_date' =>   '2019-04-03 01:00:00',
              'withdraw_date' => '2019-04-03 01:00:00',
              'end_date' =>      '2019-05-02 01:49:57',
              'user_service_id' => $us->id,
              'service_id' => $next_service->id,
              'withdraw_id' => $wd->id,
          }
    , 'Check withdraw for next service');

    my $balance_after_create = $user->get->{balance};
    is ( $balance_after_create, $start_balance - 100, 'Check balance after switch');
};

done_testing();
