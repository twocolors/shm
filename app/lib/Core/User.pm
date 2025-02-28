package Core::User;

use v5.14;

use parent 'Core::Base';
use Core::Base;
use Core::Utils qw(
    switch_user
    is_email
    passgen
    now
    get_cookies
);
use Core::Const;

use Digest::SHA qw(sha1_hex);

sub table { return 'users' };

sub structure {
    return {
        user_id => {
            type => 'key',
        },
        partner_id => {
            type => 'number',
            hide_for_user => 1,
        },
        login => {
            type => 'text',
            required => 1,
        },
        password => {
            type => 'text',
            required => 1,
            hide_for_user => 1,
        },
        type => {
            type => 'number',
            default => 0,
        },
        created => {
            type => 'now',
        },
        last_login => {
            type => 'date',
        },
        discount => {
            type => 'number',
            default => 0,
        },
        balance => {
            type => 'number',
            default => 0,
        },
        credit => {
            type => 'number',
            default => 0,
        },
        comment => {
            type => 'text',
            hide_for_user => 1,
        },
        dogovor => {
            type => 'text',
        },
        block => {
            type => 'number',
            default => 0,
        },
        gid => {
            type => 'number',
            default => 0,
        },
        perm_credit => {
            type => 'number',
            default => 0,
            hide_for_user => 1,
        },
        full_name => {
            type => 'text',
            allow_update_by_user => 1,
        },
        can_overdraft => {
            type => 'number',
            default => 0,
        },
        bonus => {
            type => 'number',
            default => 0
        },
        phone => {
            type => 'text',
            allow_update_by_user => 1,
        },
        verified => {
            type => 'number',
            default => 0,
        },
        create_act => {
            type => 'number',
            default => 1,
        },
        settings => {
            allow_update_by_user => 1,
            type => 'json',
            value => undef
        },
    };
}

sub init {
    my $self = shift;
    my %args = (
        @_,
    );

    unless ( $self->{user_id} ) {
        $self->{user_id} = $self->user_id;
    }

    return $self;
}

sub _id {
    my $self = shift;
    my %args = (
        _id => undef,
        @_,
    );

    my $user_id;
    if ( $args{_id} ) {
        $user_id = $args{_id};
    } elsif ( my $id = $self->get_user_id ) {
        $user_id = $id;
    }

    return $user_id || get_service('config')->local->{user_id};
}

sub authenticated {
    my $self = shift;
    my $config = get_service('config');
    if ( my $user_id = $config->local('authenticated_user_id') ) {
        return get_service('user', _id => $user_id );
    } else {
        return $self;
    }
}

sub events {
    return {
        'payment' => {
            event => {
                title => 'user payment',
                kind => 'UserService',
                method => 'activate_services',
            },
        },
    };
}

sub crypt_password {
    my $self = shift;
    my %args = (
        salt => undef,
        password => undef,
        @_,
    );

    return sha1_hex( join '--', $args{salt}, $args{password} );
}

sub auth {
    my $self = shift;
    my %args = (
        login => undef,
        password => undef,
        @_,
    );

    $args{login} = lc( $args{login} );

    return undef unless $args{login} || $args{password};

    my $password = $self->crypt_password(
        salt => $args{login},
        password => $args{password},
    );

    my ( $user_row ) = $self->_list(
        where => {
            login => $args{login},
            password => $password,
        }
    );
    return undef unless $user_row;

    my $user = $self->id( $user_row->{user_id} );
    return undef if $user->is_blocked;

    $user->set( last_login => now );

    return $user;
}

sub passwd {
    my $self = shift;
    my %args = (
        password => undef,
        @_,
    );

    my $report = get_service('report');
    unless ( $args{password} ) {
        $report->add_error('Password is empty');
        return undef;
    }

    my $user = $self;

    if ( $args{admin} && $args{user_id} ) {
        $user = get_service('user', _id => $args{user_id} );
    }

    my $password = $user->crypt_password(
        salt => $user->get_login,
        password => $args{password},
    );

    get_service('sessions')->delete_user_sessions( user_id => $self->user_id );

    $user->set( password => $password );
    return scalar $user->get;
}

sub set_new_passwd {
    my $self = shift;
    my %args = (
        len => 10,
        @_,
    );

    my $new_password = passgen( $args{len} );
    $self->passwd( password => $new_password );

    return $new_password;
}

sub gen_session {
    my $self = shift;
    my %args = (
        usi => undef,
        @_,
    );

    my $session_id = get_service('sessions')->add(
        user_id => $self->id,
        settings => {
            $args{usi} ? ( usi => $args{usi} ) : (),
        },
    );

    return {
        id => $session_id,
    };
}

sub passwd_reset_request {
    my $self = shift;
    my %args = (
        email => undef,
        @_,
    );

    my ( $user ) = $self->_list(
        where => {
            login => $args{email},
        },
    );

    unless ( $user ) {
        # TODO: search in profiles
    }

    if ( $user ) {
        switch_user( $user->{user_id} );
        $self = $self->id( $user->{user_id} );

        if ( $self->is_blocked ) {
            return { msg => 'User is blocked' };
        }

        $self->make_event( 'user_password_reset' );
    }

    return { msg => 'Successful' };
}

sub is_blocked {
    my $self = shift;

    return $self->get_block();
}

sub validate_attributes {
    my $self = shift;
    my $method = shift;
    my %args = @_;

    my $report = get_service('report');
    return $report->is_success if $method eq 'set';

    unless ( $args{login} ) {
        $report->add_error('Login is empty');
    }
    unless ( $args{login}=~/^[\w\d@._-]+$/ ) {
        $report->add_error('Login is short or incorrect');
    }

    unless ( $args{password} ) {
        $report->add_error('Password is empty');
    }
    if ( length $args{password} < 6 ) {
        $report->add_error('Password is short');
    }

    return $report->is_success;
}

sub reg {
    my $self = shift;
    my %args = (
        login => undef,
        password => undef,
        partner_id => undef,
        @_,
    );

    $args{login} = lc( $args{login} );

    my $password = $self->crypt_password(
        salt => $args{login},
        password => $args{password},
    );

    my $partner_id = delete $args{partner_id} || get_cookies('partner_id');
    if ( $partner_id ) {
        $args{partner_id} = $partner_id if $self->id( $partner_id );
        delete $args{partner_id} if $partner_id == $self->id;
    }

    my $user_id = $self->add( %args, password => $password );

    unless ( $user_id ) {
        get_service('report')->add_error('Login already exists');
        return undef;
    }

    return scalar get_service( 'user', _id => $user_id )->get;
}

sub services {
    my $self = shift;
    return get_service('UserService', user_id => $self->id );
}

sub set {
    my $self = shift;
    my %args = ( @_ );

    if ( $args{block} ) {
        get_service('sessions')->delete_user_sessions( user_id => $self->user_id );
    }

    return $self->SUPER::set( %args );
}

sub set_balance {
    my $self = shift;
    my %args = (
        balance => 0,
        credit => 0,
        bonus => 0,
        @_,
    );

    my $data = join(',', map( "$_=$_+?", keys %args ) );
    my $ret = $self->do("UPDATE users SET $data WHERE user_id=?", values %args, $self->id );

    $self->reload() if $ret;

    return $ret;
}

sub set_bonus {
    my $self = shift;
    my %args = (
        bonus => 0,
        comment => undef,
        @_,
    );

    return undef if $args{bonus} == 0;

    my $bonus_id = $self->bonus->add( %args );

    $self->set_balance( bonus => $args{bonus} );

    return $bonus_id;
}

sub payment {
    my $self = shift;
    my %args = (
        money => 0,
        @_,
    );

    if ( $args{user_id} ) {
        switch_user( $args{user_id} );
        $self = $self->id( $args{user_id} );
    }

    my $pays = $self->pays;
    my $pay_id;
    unless ( $pay_id = $pays->add( %args ) ) {
        get_service('report')->add_error("Can't make payment");
        return undef;
    }

    $self->set_balance( balance => $args{money} );
    $self->add_bonuses_for_partners( $args{money} );

    $self->make_event( 'payment' );
    return scalar $pays->id( $pay_id )->get;
}

sub add_bonuses_for_partners {
    my $self = shift;
    my $payment = shift;

    my $partner_id_1 = $self->get_partner_id;
    return undef unless $partner_id_1;

    my $percent = get_service('config')->data_by_name('billing')->{partner}->{income_percent};
    return undef unless $percent;

    my $bonus = $payment * $percent / 100;

    if ( my $partner_1 = $self->id( $partner_id_1 ) ) {
        $partner_1->set_bonus( bonus => $bonus,
            comment => {
                from_user_id => $self->id,
                percent => $percent,
            },
        );
    }
}

sub pays {
    my $self = shift;
    return get_service('pay', user_id => $self->id );
}

sub bonus {
    my $self = shift;
    return get_service('bonus', user_id => $self->id );
}

sub withdraws {
    my $self = shift;
    return get_service('withdraw', user_id => $self->id );
}

sub is_admin {
    my $self = shift;
    return $self->get_gid;
}

sub list_for_api {
    my $self = shift;
    my %args = (
        admin => 0,
        @_,
    );

    if ( $args{admin} ) {
        $args{where} = { user_id => $args{user_id} } if $args{user_id};
    } else {
        $args{where} = { user_id => $self->id };
    }

    return $self->SUPER::list_for_api( %args );
}

sub profile {
    my $self = shift;

    my $profile = get_service("profile");
    my ( $item ) = $profile->_list(
        where => {
            user_id => $self->id,
        },
        limit => 1,
    );

    return %{ $item->{data} || {} };
}

sub emails {
    my $self = shift;

    my %profile = $self->profile;

    my $email = $profile{email};
    unless ( $email ) {
        if (is_email( $self->get_login)) {
            $email = $self->get_login;
        }
    }
    return $email;
}

sub referrals_count {
    my $self = shift;

    my @count = $self->_list(
        where => {
            partner_id => $self->id,
        },
    );

    return scalar @count;
}


1;

