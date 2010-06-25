#!/usr/bin/perl
#
# DW::Mood - Provide mood theme support. Replaces ljmood.pl from LJ.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Mood;

use strict;
use warnings;


### MOOD (CLASS) METHODS

# load list of moods from DB (adapted from LJ::load_moods)
# arguments: none
# returns: true
sub load_moods {
    return 1 if $LJ::CACHED_MOODS;
    my $dbr = LJ::get_db_reader();
    my $data = $dbr->selectall_arrayref(
        "SELECT moodid, mood, parentmood, weight FROM moods" );
    die $dbr->errstr if $dbr->err;

    $LJ::CACHED_MOOD_MAX ||= 0;

    foreach my $row ( @$data ) {
        my ( $id, $mood, $parent, $weight ) = @$row;
        $LJ::CACHE_MOODS{$id} =
            { name => $mood, parent => $parent, id => $id, weight => $weight };
        $LJ::CACHED_MOOD_MAX = $id if $id > $LJ::CACHED_MOOD_MAX;
    }
    return $LJ::CACHED_MOODS = 1;
}

# get list of moods from cache (adapted from LJ::get_moods)
# arguments: class
# returns: hashref
sub get_moods {
    my ( $self ) = @_;
    $self->load_moods;
    return \%LJ::CACHE_MOODS;
}

# mood name to id (or undef) (adapted from LJ::mood_id)
sub mood_id {
    my ( $self, $mood ) = @_;
    return undef unless $mood;

    $self->load_moods;
    foreach my $m ( values %LJ::CACHE_MOODS ) {
        return $m->{id} if $mood eq $m->{name};
    }
    return undef;
}

# mood id to name (or undef) (adapted from LJ::mood_name)
sub mood_name {
    my ( $self, $moodid ) = @_;
    return undef unless $moodid;

    $self->load_moods;
    my $m = $LJ::CACHE_MOODS{$moodid};
    return $m ? $m->{name} : undef;
}

# associate local moods with moodids on other sites
# arguments: local moodid or mood; external siteid
# returns: id of mood on the remote site, or 0 on failure
sub get_external_moodid {
    my ( $self, %opts ) = @_;

    my $siteid = $opts{siteid};
    my $moodid = $opts{moodid};
    my $mood = $opts{mood};

    return 0 unless $siteid;
    return 0 unless $moodid || $mood;

    my $mood_text = $mood ? $mood : $self->mood_name( $moodid );

    # determine which moodid on the external site
    # corresponds to the given $mood_text
    my $dbr = LJ::get_db_reader();
    my ( $external_moodid ) = $dbr->selectrow_array(
        "SELECT moodid FROM external_site_moods WHERE siteid = ?" .
        " AND LOWER( mood ) = ?", undef, $siteid, lc $mood_text );

    return $external_moodid ? $external_moodid : 0;
}


### THEME (OBJECT/CLASS) METHODS

# basic object construction: requires theme id
# arguments: theme id (required)
# returns: object reference, undef on failure
sub new {
    my ( $class, $id ) = @_;
    return undef unless $id;
    my $self = {};  # id set via object method below
    bless $self, ( ref $class ? ref $class : $class );
    return undef unless $self->id( $id );
    $self->load_moods;  # not necessary but saves effort later
    return $self->load_theme;
}

# basic get/set for theme id
# arguments: set if theme id given, get if no args
# returns: value of theme id, undef on failure
sub id {
    my ( $self, $id ) = @_;
    return undef if $id && $id !~ /^\d+$/;  # invalid id
    return $id unless ref $self;            # class method
    return $self->{id} unless $id;          # get only
    return $self->{id} = $id;               # set and return
}

# load theme data from DB (adapted from LJ::load_mood_theme)
# arguments: theme id (only required if called as class method)
# returns: object reference, undef on failure
sub load_theme {
    my ( $self, $themeid ) = @_;

    # force object path if called as class
    return $self->new( $themeid ) unless ref $self;

    # check themeid and assign it to the object
    return undef unless $themeid = $self->id( $themeid );

    # check global memory cache
    return $self if $LJ::CACHE_MOOD_THEME{$themeid};

    # check memcache
    my $memkey = [$themeid, "moodthemedata:$themeid"];
    $LJ::CACHE_MOOD_THEME{$themeid} = LJ::MemCache::get( $memkey );
    return $self if %{ $LJ::CACHE_MOOD_THEME{$themeid} || {} };

    # fall back to db
    $LJ::CACHE_MOOD_THEME{$themeid} = {};
    my $dbr = LJ::get_db_reader();

    # load picture rows from moodthemedata
    my $data = $dbr->selectall_arrayref(
        "SELECT moodid, picurl, width, height FROM moodthemedata " .
        "WHERE moodthemeid=?", undef, $themeid );
    die $dbr->errstr if $dbr->err;

    # load metadata from moodthemes
    my ( $name, $des, $is_public, $ownerid ) = $dbr->selectrow_array(
        "SELECT name, des, is_public, ownerid FROM moodthemes" .
        " WHERE moodthemeid=?", undef, $themeid );
    die $dbr->errstr if $dbr->err;

    $LJ::CACHE_MOOD_THEME{$themeid}->{moodthemeid} = $themeid;
    $LJ::CACHE_MOOD_THEME{$themeid}->{is_public} = $is_public;
    $LJ::CACHE_MOOD_THEME{$themeid}->{ownerid}   = $ownerid;
    $LJ::CACHE_MOOD_THEME{$themeid}->{name} = $name;
    $LJ::CACHE_MOOD_THEME{$themeid}->{des}  = $des;

    foreach my $d ( @$data ) {
        my ( $id, $pic, $w, $h ) = @$d;
        $LJ::CACHE_MOOD_THEME{$themeid}->{$id} =
            { pic => $pic, w => $w, h => $h };
    }

    # set in memcache
    LJ::MemCache::set( $memkey, $LJ::CACHE_MOOD_THEME{$themeid}, 3600 )
        if %{ $LJ::CACHE_MOOD_THEME{$themeid} || {} };

    return $self;
}

# object method to load a mood icon (adapted from LJ::get_mood_picture)
# arguments: moodid; hashref to assign with mood icon data
# returns: 1 on success, 0 otherwise.
sub get_picture {
    my ( $self, $moodid, $ref ) = @_;
    return 0 unless $ref && ref $ref;
    my $themeid = $self->id or return 0;

    while ( $moodid ) {
        # inheritance check
        unless ( $LJ::CACHE_MOOD_THEME{$themeid} &&
                 $LJ::CACHE_MOOD_THEME{$themeid}->{$moodid} ) {
            $moodid = defined $LJ::CACHE_MOODS{$moodid} ?
                      $LJ::CACHE_MOODS{$moodid}->{parent} : 0;
            next;
        }
        # load the data
        %{ $ref } = %{ $LJ::CACHE_MOOD_THEME{$themeid}->{$moodid} };
        $ref->{moodid} = $moodid;
        # sanitize the value of pic
        if ($ref->{pic} =~ m!^/!) {
            $ref->{pic} =~ s!^/img!!;
            $ref->{pic} = $LJ::IMGPREFIX . $ref->{pic};
        }
        # must be a good url
        $ref->{pic} = "#invalid" unless
            $ref->{pic} =~ m!^https?://[^\'\"\0\s]+$!;
        return 1;
    }
    return 0;  # couldn't find a picture anywhere in the parent chain
}

# object method: get theme description (adapted from LJ::mood_theme_des)
sub des {
    my ( $self ) = @_;
    my $themeid = $self->id or return undef;
    my $m = $LJ::CACHE_MOOD_THEME{$themeid};
    return $m ? $m->{des} : undef;
}

# clear cached theme data from memory
# arguments: theme id (only required if called as class method)
# returns: nothing
sub clear_cache {
    my ( $self, $themeid ) = @_;

    # load theme id from object if needed
    $themeid ||= $self->id if ref $self;

    # clear the caches
    LJ::MemCache::delete( [$themeid, "moodthemedata:$themeid"] );
    delete $LJ::CACHE_MOOD_THEME{$themeid};
}


1;