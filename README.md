# About

Display all process table, open files, and network connections for a PID.


![piddler](piddler.png)

# Command Line Options
```
-a        Show a_inodes.
-d        Do not dedup.
-f        Show FIFOs.
-m        Show memory mapped libraries of the REG type.
-n        Do not resolve PTR addresses.
--nc      Disable color.
-p        Show pipes.
-r        Show show VREG / files.
-t        Show shared libraries.
-u        Show unix sockets.
```

# Enviromental Variables

The enviromental variables below may be set to set the default for the
flag in question.

Unless set to defined ands set to 1, these will default to 0.

| Variable |  Description  |
| -------- | ---------------- |
| NO_COLOR | If set to 1, color will be disabled. |
| PIDDLER_dont_dedup | If set to 1, duplicate file handles are removed. |
| PIDDLER_dont_resolv | If set to 1, PTR addresses will not be resolved for network connections. |
| PIDDLER_a_inode | If set to 1, a_inode types will be shown. |
| PIDDLER_fifo | If set to 1, FIFOs will not be shown. |
| PIDDLER_memreglib | If set to 1, memory mapped libraries with the type REG will be shown. |
| PIDDLER_pipe | If set to 1, pipes will not be shown. |
| PIDDLER_txt | If set to 1, libraries with the TXT type will not be shown. |
| PIDDLER_unix | If set to 1, unix socket will not be shown. |
| PIDDLER_vregroot | If set to 1, VREG / will not be shown. |

# Installing

## FreeBSD

    pkg install perl5 p5-App-cpanminus
    cpanm Proc::ProcessTable::piddler
    
## Linux

### CentOS

    yum install cpanm
    cpanm Proc::ProcessTable::piddler

### Debian

This has been tested as working on Debian 9 minimal.

    apt install perl perl-base perl-modules make cpanminus gcc 
    cpanm Proc::ProcessTable::piddler
