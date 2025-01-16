---
title: mit6.s081 lab1
date: 2025-01-16 17:06:06
tags: mit6.s081
---

### Boot xv6

这个Lab在0中已经提及过 不再赘述



### Sleep

第一个实打实的Lab，大致上是过一下整个编写代码的流程，只需要做命令行校验和系统调用就可以了。

```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"

int main(int argc, char* argv[]) {
  int n;

  if (argc != 2) {
    fprintf(2, "Please enter a number!\n");
    exit(1);
  } else {

    n = atoi(argv[1]);
    
    if (n != 0) {
      sleep(n);
    
    } else {
      fprintf(2, "Please enter a number!\n");
      exit(1);
    }
    exit(0);
  }
}
```

编写完成之后，根据指引在`Makefile`中的第179行中加入，注册即可

```makefile
UPROGS=\
	$U/_cat\
	$U/_echo\
	$U/_forktest\
	$U/_grep\
	$U/_init\
	$U/_kill\
	$U/_ln\
	$U/_ls\
	$U/_mkdir\
	$U/_rm\
	$U/_sh\
	$U/_stressfs\
	$U/_usertests\
	$U/_grind\
	$U/_wc\
	$U/_zombie\
	$U/_sleep\
```

写完之后 命令行执行测试程序

```bash
chenz@Chenzc:~/lab$ sudo python3 grade-lab-util sleep

make: 'kernel/kernel' is up to date.
== Test sleep, no arguments == sleep, no arguments: OK (3.3s)
== Test sleep, returns == sleep, returns: OK (0.9s)
== Test sleep, makes syscall == sleep, makes syscall: OK (1.0s)
```



### Pingpong

创建两个进程 通过pipe在他们之间心跳通信

```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"

// 两个进程 父进程先write到 子进程 ping
//         子进程后write到 父进程 pong

int main(int argc, char* argv[]) {
  int p[2];    //as chan
  int buf[2];  //msg buffer

  pipe(p);

  char* pingMsg = "i";
  char* pongMsg = "o";

  if (fork() == 0) {
    // 子进程
    int rr;
    rr = read(p[0], buf, 1);
    if (rr != 1) {
      fprintf(2, "child process read error\n");
      exit(1);
    }

    close(p[0]);
    printf("%d: received ping\n");

    int wr;
    wr = write(p[1], pongMsg, 1);
    if (wr != 1) {
      fprintf(2, "child process write error\n");
      exit(1);
    }

    close(p[1]);
    exit(0);

  } else {
    // 父进程
    int pwr;
    pwr = write(p[1], pingMsg, 1);
    if (pwr != 1) {
      fprintf(2, "parent process write error\n");
      exit(1);
    }

    close(p[1]);

    wait(0);
    // wait系统调用下 等待某个线程的任一子进程结束任务即返回
    // 其中填入的形参本应是一个地址 这个地址将会记录子进程退出时状态
    // 这里填入了0 相当于填入了NULL 不记录子进程的退出状态

    int prr;
    prr = read(p[0], buf, 1);
    if (prr != 1) {
      fprintf(2, "parent process read error\n");
    }

    printf("%d: received pong\n",getpid());
    close(p[0]);
    exit(0);
  }
}
```

主要是考察系统调用 `wait() read() write() pipe()` 这几个

成功效果是 （进程号可忽略）

```bash
$ pingpong
12224: received ping
3: received pong
$ pingpong
12224: received ping
5: received pong
```

测试可得

```bash
chenz@Chenzc:~/lab$ sudo python3 grade-lab-util pingpong
make: 'kernel/kernel' is up to date.
== Test pingpong == pingpong: OK (3.4s)
    (Old xv6.out.pingpong failure log removed)
```



### Primes

并发处理质数，本质上从2（第一个质数开始），假如某个数是素数，那么他就会成为其中一个筛选器。判断某个数是否质数，只需要经过目前的所有筛选器进行判断，判断是否他们的倍数，如果不是的话，就证明了该数是质数。

![](https://swtch.com/~rsc/thread/sieve.gif)

乍一看有点像链表 关键在于怎么实现单个数经过不同的筛选器的过程 这一过程本质上是同步的 **但是各个筛选器都可以异步进行** 并发主要是从这个特点入手

利用阻塞实现有点像事件驱动机制的效果

通过一个主线程发布自然数流，经过这个流将数传到各个筛选器当中。

筛选器之间本质上是一个递归传输的关系，这么写的好处就是不需要显式的维护每一个fd之间的关系。而是通过递归这一过程本身进行维护释放 `close()`

代码如下：

```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"

void primes(int* fd) {
  // 子进程关闭掉对应的写口 因为子进程不需要写
  close(fd[1]);
  
  int v;
  int l = read(fd[0], (void*)&v, sizeof(v));
  if (l != sizeof(v)) {
    if(l == 0){
        // EOF
        exit(0);
    }
    fprintf(2, "Read Error!\n");
    exit(1);
  }
  //   进来到这里就代表是新开了一个筛选器 可以理解成递归
  printf("prime %d\n", v);

  int nextFd[2];
  pipe(nextFd);

  if (fork() == 0) {
    primes(nextFd);

  } else {
    close(nextFd[0]);

    int vv;
    while (read(fd[0], (void*)&vv, sizeof(vv)) == sizeof(vv)) {
      // 判断是不是素数
      if (vv % v != 0) {
        if (write(nextFd[1], (void*)&vv, sizeof(vv)) != sizeof(vv)) {
          fprintf(2, "Write Error!\n");
          exit(1);
        }
      }
    }
    close(fd[0]);
    close(nextFd[1]);
    wait(0);
  }

  exit(1);
}

int main(int argc, char* argv[]) {
  int fd[2];
  pipe(fd);
  if (fork() == 0) {
    primes(fd);
  } else {
    // generate线程 将所有数都传进去
    close(fd[0]);
    for (int i = 2; i < 36; i++) {
      if (write(fd[1], (void*)&i, sizeof(i)) != sizeof(i)) {
        fprintf(2, "Write fail!\n");
        exit(1);
      }
    }
    close(fd[1]);
    wait(0);
    // 等待子进程任务结束
  }

  exit(0);
}
```

注意，代码中是由一个类似饿加载的思想，在我初始化某个筛选器的时候，会一并把他之后的筛选器也创建出来。这一预备创建的筛选器具备自身的读pipe，处于阻塞状态（第10行），假如需要创建新的话，就以当前值为筛选值（最大的质数），一并初始化，创建下一个新&空筛选器。

执行结果及测试有：

```bash
$ primes
prime 2
prime 3
prime 5
prime 7
prime 11
prime 13
prime 17
prime 19
prime 23
prime 29
prime 31
```

```bash
chenz@Chenzc:~/lab$ sudo python3 grade-lab-util primes
[sudo] password for chenz:
make: 'kernel/kernel' is up to date.
== Test primes == primes: OK (3.8s)
    (Old xv6.out.primes failure log removed)
```



### Find

这个lab就是通过参考`ls.c`中的目录遍历方式，实现递归查找。将整个递归的思路捋清楚就好了。

本质上就是遍历目录树，当遍历到文件夹的时候，进去递归；当遍历到文件的时候，比较文件的名字是否一样，一样则print。

代码如下：

```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/fs.h"
#include "user/user.h"

int strcontain(const char* p, const char* q) {
    // const char *p_start = p;    // 保留 p 的起始位置
    while (*p) {  // 遍历字符串 p 的每个字符
        const char* p_temp = p;
        const char* q_temp = q;

        while (*q_temp && *p_temp && *q_temp == *p_temp) {
            q_temp++;
            p_temp++;
        }

        if (*q_temp == '\0') {  // 如果 q 全部匹配完，说明找到子串
            return 1;
        }
        p++;  // 移动到 p 的下一个位置
    }
    return 0;  // 如果遍历完未找到，返回 0
}

// 需要遍历该目录下的所有文件以及文件夹
// 对于文件夹需要递归遍历其下的所有文件
// 每一个文件有自己的fd 通过fd获取mtdata

void find(char* path, char* target) {
    char buf[512], *p;
    // dirent 提供目录项的基本信息
    // stat 提供文件的详细信息
    struct stat st;
    struct dirent de;
    int fd;

    if ((fd = open(path, 0)) < 0) {
        fprintf(2, "find: cannot open %s\n", path);
        exit(1);
    }

    // 获取目标目录的格式并校验
    if (fstat(fd, &st) < 0) {
        fprintf(2, "find: cannot stat %s\n", path);
        close(fd);
        exit(1);
    }

    // 判断是否文件夹
    if (st.type != T_DIR) {
        fprintf(2, "find: %s is not a directory\n", path);
        close(fd);
        return;
    }

    // 格式化各种路径
    if (strlen(path) + 1 + DIRSIZ + 1 > sizeof buf) {
        printf("find: path too long\n");
        close(fd);
        return;
    }

    // 这里是将p指针固定在父路径的尾部 这样子每一次循环的时候 只需要修改p之后的内容 就可实现递归
    strcpy(buf, path);      // 将path复制到变量buf之中
    p = buf + strlen(buf);  // 将指针p指向buf字符串的结尾
    *p++ = '/';             //结尾加上“/” 为之后进行查找时备用

    // 回溯递归校验查找
    while (read(fd, &de, sizeof(de)) == sizeof(de)) {
        // 校验是否合法 不合法跳过
        if (de.inum == 0) {
            continue;
        }

        if (strcmp(de.name, ".") == 0 || strcmp(de.name, "..") == 0)
            continue;

        // de.name 是子文件的名字 将子文件与父路径进行拼接
        memmove(p, de.name, DIRSIZ);
        // 确保路径的结尾是"/0" 保证他是一个合法的字符串
        p[DIRSIZ] = 0;

        // 判断它的类型是文件还是文件夹 假如是文件夹的话 递归查找 是文件的话 直接再次结束判断即可
        if (stat(buf, &st) < 0) {
            printf("find: cannot stat %s\n", buf);
            continue;
        }

        switch (st.type) {
            case T_FILE:
                if (strcontain(de.name, target) == 1) {
                    // 合法的话 打印该文件的名字
                    printf("%s\n", buf);
                }
                break;
            case T_DIR:
                // 递归进行查找
                find(buf, target);
                break;
        }
    }
    close(fd);
}

//  总体的思路应该是先通过一个while循环 进行遍历当前目录
//   对每一个文件都进行一次read 然后fstat 判断它的类型 假如是文件夹 则修改路径 然后直接进行递归即可
int main(int argc, char* argv[]) {

    if (argc != 3) {
        fprintf(2, "Please enter a path and str\n");
        exit(1);
    }

    find(argv[1], argv[2]);

    exit(0);
}
```

如代码 递归的时候只需要传递对应的路径和查找目标字符串就可以了 

其实也可以将目标字符串提取为全局变量 这样可能会根据递归的深度增加 进一步优化查找空间效率 

但是lab测试程序可能比较浅 实测没有测出明显的变化 执行效果及测试如下

```bash
$ find . b
./zombie
./a/b
./b
```

```bash
chenz@Chenzc:~/lab$ sudo python3 grade-lab-util find
make: 'kernel/kernel' is up to date.
== Test find, in current directory == find, in current directory: OK (3.8s)
== Test find, recursive == find, recursive: OK (1.3s)
```



### Xargs

这个命令可能相比起来没有那么熟悉 本质上的作用就是将从标准输入流获取到的数据根据`\n`进行区分 并且分批以参数形式发给xargs中的执行命令 直接说一个具体的执行效果例子可能好一点：

```bash
$ echo a\nb | xargs echo c
# 该命令的输出效果应该是：
$ ca cb
```

注意这里不需要实现Unix中实际的优化之类的，（Lab说的 是啥我也不清楚）

理解了其实就不是很难 分割字符串处理 然后通过`fork() & exec()`创建子进程执行目标命令，父进程`wait()`结束就可以了

上代码：

```c
#include "kernel/types.h"
#include "kernel/stat.h"
#include "kernel/param.h"
#include "user/user.h"
#define NULL ((void*)0)

// 本质上是将标准输入流的数据 通过换行符对每一行进行标识
// 对于每一行都分别执行xarg后的命令

void xargs(char* func, char* cmd[]) {

    // fork子进程exec执行命令 父进程wait获取执行结果并返回
    if (fork() == 0) {
        if (exec(func, cmd) < 0) {
            fprintf(2, "xargs: exec %s failed!\n", func);
            exit(1);
        }
    } else {
        wait(0);
    }
}

int main(int argc, char* argv[]) {

    if (argc < 2) {
        fprintf(2, "xargs: enter args\n");
        exit(1);
    }

    char buf[512], *p;
    p = buf;
    // 装配执行参数
    char* cmd[MAXARG];
    char* func = argv[1];

    int i = 1;
    int cmd_args = 0;
    while (i < argc) {
        cmd[cmd_args++] = argv[i++];
    }

    // 从输入流中获取数据 read
    char c;
    while (read(0, &c, 1)) {
        if (c != '\n') {
            // 动态添加
            *p++ = c;

            // p为当前操作的字符串的末尾 buf则为开头 两者相减为目前操作的字符串的真实长度
            if (p - buf >= sizeof(buf)) {
                fprintf(2, "xargs: input too lang\n");
                exit(1);
            }

        } else if (c == '\n') {
            *p = '\0';
            // 组装运行参数
            cmd[cmd_args] = buf;
            cmd[cmd_args + 1] = 0;

            // 执行
            xargs(func, cmd);

            // 恢复现场
            p = buf;
        }
    }

    // 处理最后一行
    if (p != buf) {
        *p = '\0';
        cmd[cmd_args] = buf;
        cmd[cmd_args + 1] = 0;
        xargs(func, cmd);
    }

    exit(0);
}
```

这里在传输buf字符串的时候，没有`strcpy()`，而是直接传了原来的文件。这主要是因为在fork的时候，子进程会复制父进程一份所有的地址空间（抛开COW等优化不谈），其中就包括了会创建一份buf的副本。

执行效果与测试程序如下： （注意 在命令行直接`echo a\nb`这样仿作标准输入流是不可行的 不会正确识别到换行符 `TODO`）

```bash
$ sh < xargstest.sh
$ $ $ $ $ $ hello
hello
hello
$ $
```

```bash
chenz@Chenzc:~/lab$ sudo python3 grade-lab-util xargs
make: 'kernel/kernel' is up to date.
== Test xargs == xargs: OK (2.9s)
```





### 可选Lab TODO


