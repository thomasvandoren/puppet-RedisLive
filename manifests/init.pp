# == Class: redis_live
#
# Install RedisLive to monitor one or more redis instances. Uses a local redis
# instance to store data.
#
# === Requirements
#
# puppetlabs-git module - to install git
# puppetlabs-vcsrepo module - to clone the RedisLive repo
# thomasvandoren-redis module - to setup the local redis instance
#
# === Paramaters
#
# TODO
#
# === Examples
#
#   include redis_live
#
#   TODO!
#
# === Authors
#
# Thomas Van Doren
#
# === Copyright
#
# Copyright 2013 Thomas Van Doren, unless otherwise noted
#
class redis_live (
  $redis_servers = [{'server' => '127.0.0.1', 'port' => '6379'}],
  $redis_stats_server = {'server' => '127.0.0.1', 'port' => '6380', 'maxmemory' => '512mb'},
  $crontab_mailto = "root@${::fqdn}"
  ) {
  # Ensure git is installed.
  include git

  # RedisLive python dependencies.
  $redis_live_user = 'redis-live'
  $redis_live_group = 'redis-live'
  $redis_live_home = "/var/lib/${redis_live_user}"
  $redis_live_clone = "${redis_live_home}/RedisLive-src"
  $redis_live_config = "${redis_live_clone}/src/redis-live.conf"
  $python_packages = ['tornado', 'redis', 'hiredis', 'python-dateutil']

  # Create a system user/group to run the webserver and the monitor.
  group { $redis_live_group:
    ensure => present,
    system => true,
  }
  user { $redis_live_user:
    ensure  => present,
    gid     => $redis_live_group,
    home    =. $redis_live_home,
    system  => true,
    require => Group[$redis_live_group],
  }

  # Setup the RedisLive user home directory.
  file { $redis_live_home:
    ensure => directory,
    owner  => $redis_live_user,
    group  => $redis_live_group,
    mode   => '0755',
    require => User[$redis_live_user],
  }

  # Clone the RedisLive repo from GitHub.
  vcsrepo { $redis_live_clone:
    ensure   => present,
    provider => 'git',
    source   => 'git://github.com/kumarnitin/RedisLive.git',
    revision => '285fc4b1c8e3a3438e7a9cdbd13a2f826baa8032',  # master as of 2013-03-26 ish
    owner    => $redis_live_user,
    group    => $redis_live_group,
    require  => File[$redis_live_home],
  }

  # Write the config file
  file { 'redis-live.conf':
    ensure  => present,
    path    => $redis_live_config,
    owner   => $redis_live_user,
    group   => $redis_live_group,
    mode    => '0644',
    content => template('redis_live/redis-live.conf.erb'),
    require => Vcsrepo[$redis_live_clone],
  }

  # Install the python dependencies globally.
  package { $python_packages:
    ensure   => present,
    provider => 'pip',
  }

  # Install the redis instance for recording data.
  $redis_stats_port = $redis_stats_server["port"]
  $redis_stats_ipaddress = $redis_stats_server["server"]
  $redis_stats_maxmemory = $redis_stats_server["maxmemory"]
  class { 'redis':
    version            => '2.6.11',
    redis_port         => $redis_stats_port,
    redis_bind_address => $redis_stats_ipaddress,
    redis_max_memory   => $redis_stats_maxmemory,
  }

  # Install the monitor as a crontab.
  cron { 'redis-monitor':
    ensure      => present,
    command     => "cd ${redis_live_clone}/src && python redis-monitor.py --duration 30",
    user        => $redis_live_user,
    environment => ['PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
                    "MAILTO=${crontab_mailto}"],
    minute      => '*',
    require     => [ Package[$python_packages], File['redis-live.conf'] ],
  }

  # Setup an upstart job to manage the tornado server.
  file { 'redis-live.upstart':
    ensure  => present,
    path    => '/etc/init/redis-live.conf',
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('redis_live/redis-live.upstart.erb'),
    notify  => Service['redis-live'],
  }

  # Manage the redis live service.
  service { 'redis-live':
    ensure  => 'running',
    enable  => true,
    require => File['redis-live.upstart'],
  }
}
