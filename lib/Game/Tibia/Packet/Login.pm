use strict;
use warnings;
no warnings 'uninitialized';
use v5.16.0;
package Game::Tibia::Packet::Login;

# ABSTRACT: Login packet support for the MMORPG Tibia
# VERSION

use Carp;
use File::ShareDir 'dist_file';
use Crypt::OpenSSL::RSA;
use Digest::Adler32;
use Game::Tibia::Packet;
use Scalar::Util qw(blessed);

=pod

=encoding utf8

=head1 NAME

Game::Tibia::Packet::Login - Login packet support for the MMORPG Tibia


=head1 SYNOPSIS

    use Game::Tibia::Packet::Login;


=head1 DESCRIPTION

Decodes Tibia Login packets into hashes and vice versa. By default uses the OTServ RSA key, but allows different RSA keys to be supplied. Version 9.80 and above is not supported.

=cut

my $otserv = Crypt::OpenSSL::RSA->new_private_key(
    do { local $/; open my $rsa, dist_file('Game-Tibia-Packet', 'otserv.private') or die "Couldn't open private key $!"; <$rsa>; }
);

=head1 METHODS AND ARGUMENTS

=over 4

=item new(version => $version, [$character => undef, packet => $packet, rsa => OTSERV])

Constructs a new C<Game::Tibia::Packet::Login> instance of version C<$version>. If C<packet> is supplied, decryption using the supplied rsa private key is attempted. If no C<rsa> is supplied, the OTServ RSA key is used. If a C<$character> name is supplied, it's assumed to be a game server login packet.

=cut

sub new {
    my $class = shift;
    
    my $self = {
        packet => undef,
        rsa    => $otserv,

        @_
    };

    $self->{version} //= $self->{versions}{client}{VERSION};
    croak 'A protocol version < 9.80 must be supplied' if !defined $self->{version} || $self->{version} >= 980;

    $self->{versions}{client} = Game::Tibia::Packet::version($self->{version});

    if ($self->{versions}{client}{rsa}) {
        if (defined $self->{rsa} and !blessed $self->{rsa}) {
            $self->{rsa} = Crypt::OpenSSL::RSA->new_private_key($self->{rsa});
        }
        $self->{rsa}->use_no_padding if defined $self->{rsa};
    }

    if (defined $self->{packet}) {
        (my $len, $self->{os}, $self->{versions}{client}{VERSION}, $self->{versions}{spr}, $self->{versions}{dat}, $self->{versions}{pic}, my $payload)
            = unpack 'v x(S S L3)< a*', $self->{packet};

        if ($self->{versions}{client}{rsa}) {
            $payload = $self->{rsa}->decrypt($payload);
            croak q(Decoded RSA doesn't start with zero.) if $payload !~ /^\0/;
            $payload = substr $payload, 1;
        }

        if ($self->{versions}{client}{xtea}) {
            ($self->{XTEA}, $payload) = unpack 'a16 a*', $payload;
        }

        my $acc_data_pattern = $self->{versions}{client}{accname} ? '(S/a S/a)<' : '(V S/a)<';
        ($self->{account}, $self->{password}, $self->{hwinfo}, $self->{padding})
            = unpack "$acc_data_pattern a47 a*", $payload;
    }

    bless $self, $class;
    return $self;
}

=item finalize([$rsa])

Finalizes the packet. encrypts with RSA and prepends header

=cut


sub finalize {
    my $self = shift;
    my $rsa = shift // $self->{rsa};
    $self->{rsa}->use_no_padding if defined $self->{rsa};
    $self->{versions}{client} = Game::Tibia::Packet::version $self->{versions}{client} unless ref $self->{versions}{client};

    my $payload = '';
    if ($self->{versions}{client}{rsa}) {
        $rsa = Crypt::OpenSSL::RSA->new_private_key($rsa) unless blessed $rsa;
        $rsa->size == 128
            or croak "Protocol $self->{versions}{client}{VERSION} expects 128 bit RSA key, but ${\($rsa->size*8)} bit were provided";
        $payload .= "\0";
    }

    $self->{packet} = defined $self->{character} ? "\x0a" : "\x01";
    $self->{packet} .= pack '(S2)<', $self->{os}, $self->{versions}{client}{VERSION};

    $self->{packet} .= defined $self->{character} ? "\0" :
    pack '(L3)<', $self->{versions}{spr}, $self->{versions}{dat}, $self->{versions}{pic};

    my $acc_pattern = $self->{versions}{client}{acc_name} ? '(S/a)<' : 'V';

    $payload .= $self->{XTEA} if $self->{versions}{client}{xtea};
    $payload .= pack $acc_pattern, $self->{account};
    $payload .= pack '(S/a)<', $self->{character} if defined $self->{character};
    $payload .= pack '(S/a)<', $self->{password};
    $payload .= pack 'a47', $self->{hwinfo} if defined $self->{hwinfo} && $self->{hwinfo} ne '';

    if ($self->{versions}{client}{rsa}) {
        my $padding_len = 128 - length($payload);
        $self->{padding} //= '';
        $payload .= pack "a$padding_len", $self->{padding};
        $payload = $self->{rsa}->encrypt($payload);
    }
    $self->{packet} .= $payload;


    if ($self->{versions}{client}{adler32}) {
        my $a32 = Digest::Adler32->new;
        $a32->add($self->{packet});
        my $digest = unpack 'H*', pack 'N', unpack 'L', $a32->digest;
        $self->{packet} = $digest.$self->{packet};
    }

    $self->{packet} = pack("S/a", $self->{packet});

    $self->{packet};
}

1;
__END__

=back

=head1 GIT REPOSITORY

L<http://github.com/athreef/Game-Tibia-Packet>

=head1 SEE ALSO

L<Game::Tibia::Packet>

L<Game::Tibia::Packet::Charlist>

=head1 AUTHOR

Ahmad Fatoum C<< <athreef@cpan.org> >>, L<http://a3f.at>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 Ahmad Fatoum

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


