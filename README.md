# rubin
[![Build Status](https://travis-ci.org/phime42/rubin.svg)](https://travis-ci.org/phime42/rubin)
[![Code Climate](https://codeclimate.com/github/phime42/rubin/badges/gpa.svg)](https://codeclimate.com/github/phime42/rubin)
[![Dependency Status](https://gemnasium.com/phime42/rubin.svg)](https://gemnasium.com/phime42/rubin)  
An IRC/E-Mail/XMPP collector backend written in Ruby. Early-stage work in progress

## Overview
- connects to various message sources (IRC-only, at the moment)
- does only write encrypted data to disk (NaCl)
- modular architecture
- RESTful API

This project aims to replace classical IRC bouncers in a safe fashion.
Every piece of data written to disk is encrypted via djb's NaCl crypto library.

Prerequisities: Ruby, Bundler (https://bundler.io), SQLitebrowser (http://sqlitebrowser.org)

## API
This project utilizes a RESTful API.

#### Pull a message from the database
`/key-ID/message-ID`
e.g.: `http://foo.bar/42/9238`

#### Show all message-IDs for the key-ID
`/key-ID/all
e.g.: `http://foo.bar/42/all`

#### Output host key
`/key`
e.g.: `http://foo.bar/key`

#### more to come ;)


## Usage
At the moment, this project is not ready for the end user since it is still developed.

- download project
- change to the project directory
- `bundle install`
- `ruby classes.rb`
- quit program
- open SQLitebrowser
- open table `clients`
- add your IRC server:
  - `id - incrementing number. Must not be used twice`
  - `description - the name of your IRC channel. For example: foobar123`
  - `host - URL of the IRC server with port. Only SSL-encrypted connections are supported. For example: https://irc.freenode.org:7000)`
  - `type - since IRC is the only supported protocol at the moment: irc`
  - `nick - your desired nick`
  - `realname - your desired realname`
  - `channel - the channel that should be listened`
- add a client
  - build a client ;)
  - create a NaCl keypair (preferably with RbNaCl, other key formats were not tested)
  - Base64 the public key
  - edit the `keys` table:
    - `id - incrementing number`
    - `description - your internal name for that device`
    - `private key - DO NOT edit this field! Bad things would happen... (every saved public key with a private key is considered a host key...)
    - `revoked - 0 if the key's fresh, 1 if it is revoked. It won't be used from that moment on`
- write all changes to the database
- run `ruby classes.rb`
- enjoy! :)
