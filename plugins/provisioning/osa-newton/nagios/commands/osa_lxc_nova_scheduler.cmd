#--- Monitoring commands for OpsMgr role: osa_lxc_nova_scheduler

command[osa_lxc_procs] = sudo /etc/nagios/plugins/check-lxc.sh nova_scheduler check-procs.rb '-p nova-scheduler -w 15 -c 30 -W 1 -C 1'

command[osa_lxc_cpu]         = sudo /etc/nagios/plugins/check-lxc.sh nova_scheduler check-cpu.rb '-w 80 -c 90'
command[osa_lxc_mem]         = sudo /etc/nagios/plugins/check-lxc.sh nova_scheduler check-mem.sh '-w 250 -c 100'
command[osa_lxc_disk]        = sudo /etc/nagios/plugins/check-lxc.sh nova_scheduler check-disk.rb ''
command[osa_lxc_large_files] = sudo /etc/nagios/plugins/check-lxc.sh nova_scheduler check-for-large-files.sh '-d /var/log -s 1048576'
command[osa_lxc_slsocket]    = sudo /etc/nagios/plugins/check-lxc.sh nova_scheduler check-syslog-socket.rb ''
command[osa_lxc_eth0]        = sudo /etc/nagios/plugins/check-lxc.sh nova_scheduler check-netif.rb '-c 500 -w 350 --interfaces eth0'
command[osa_lxc_eth1]        = sudo /etc/nagios/plugins/check-lxc.sh nova_scheduler check-netif.rb '-c 500 -w 350 --interfaces eth1'
command[osa_lxc_rsyslogd]    = sudo /etc/nagios/plugins/check-lxc.sh nova_scheduler check-procs.rb '-p rsyslogd -w 15 -c 30 -W 1 -C 1'
command[osa_lxc_sshd]        = sudo /etc/nagios/plugins/check-lxc.sh nova_scheduler check-procs.rb '-p sshd -w 15 -c 30 -W 1 -C 1'
command[osa_lxc_cron]        = sudo /etc/nagios/plugins/check-lxc.sh nova_scheduler check-procs.rb '-p cron -w 15 -c 30 -W 1 -C 1'
