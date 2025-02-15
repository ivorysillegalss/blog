---
title: Linux常见命令
date: 2025-02-11 01:06:06
tags: 
---

Linux在学习的时候，通过WSL服务器等用的还挺多。但是一问起来还真不好答，遂组织一下

# Linux常见命令

## ls

列举当前目录下的所有文件

常用`ls`  `ls -l (ll)` `ls -a (la)`

对应列举文件 列举文件详细信息 列举包括隐藏文件的所有文件

```bash
chenz@Chenzc:~/test$ ls
a  b  backup  test.c
chenz@Chenzc:~/test$ ls -l
total 16
drwxr-xr-x 2 chenz chenz 4096 Jan 15 00:09 a
-rw-r--r-- 1 chenz chenz    1 Jan 15 00:08 b
drwxr-xr-x 8 chenz chenz 4096 Feb 10 17:19 backup
-rw-r--r-- 1 chenz chenz  132 Feb 11 00:51 test.c
chenz@Chenzc:~/test$ ls -a
.  ..  .a.txt  a  b  backup  test.c
```



## pwd

输出当前目录

```bash
chenz@Chenzc:~/test$ pwd
/home/chenz/test
chenz@Chenzc:~/test$ cd ../
chenz@Chenzc:~$ pwd
/home/chenz
```



## cd

切换目录

```bash
chenz@Chenzc:~/test$ pwd
/home/chenz/test
chenz@Chenzc:~/test$ cd ./
chenz@Chenzc:~$ pwd
/home/chenz/test
chenz@Chenzc:~/test$ cd ../
chenz@Chenzc:~$ pwd
/home/chenz
```



## mkdir

创建目录

```
chenz@Chenzc:~$ mkdir c
chenz@Chenzc:~$ cd c
chenz@Chenzc:~/c$
```



## rmdir

删除目录

```bash
chenz@Chenzc:~/c$ cd ../
chenz@Chenzc:~$ rmdir c
```



## touch

创建文件 or 更新文件的时间戳（跟编辑文件后效果一致）

```bash
chenz@Chenzc:~/test$ ll
-rw-r--r--  1 chenz chenz  132 Feb 11 00:51 test.c

chenz@Chenzc:~/test$ touch test.c

chenz@Chenzc:~/test$ ll
-rw-r--r--  1 chenz chenz  132 Feb 11 01:25 test.c
```



## cat

查看文件内容

```bash
chenz@Chenzc:~/test$ ls
a  b  backup  test.c
chenz@Chenzc:~/test$ cat test.c
#include <stdint.h>
typedef unsigned int uint;
typedef unsigned long uint64;

uint64 add(uint a, uint b) {
    return a + b + b;
}
```



## head / tail / more / less

查看文件开头 尾部 详细 省略内容

可以搭配某些选项实现特殊效果

```bash
chenz@Chenzc:~/test$ cat d.txt
hello world
chenz@Chenzc:~/test$ head d.txt
hello world
chenz@Chenzc:~/test$ tail d.txt
hello world
chenz@Chenzc:~/test$ more d.txt
hello world
chenz@Chenzc:~/test$ less d.txt
chenz@Chenzc:~/test$ tail -f d.txt
hello world
^C
```

如`tail -f d.txt`就可以监听最后的输出日志 在某些情况下很有用



## |

这个不能说是命令 只能说是操作符

channel 本质作用就是将一个程序的输出作为标准输入传给另外一个程序

这个的使用有很多细节 也有很多好玩的地方

例如说 | 两边的两个程序是同步运行的 是看谁执行的快 就将他的输出传给另外一个程序的

然后也可以进行多重使用等

```bash
chenz@Chenzc:~/test$ lsof | grep a | wc -l
482
```

上面的语句就是将当前运行的程序中 含有a的行数截取出来 并且计算他有多少行



## grep

过滤 筛选 标红 着重标注

![grep](\.\images\grep.jpg)



## 
