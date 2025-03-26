---
title: mit6.s081 init
date: 2025-01-10 17:05:53
tags: mit6.s081
cover: https://img.alicdn.com/imgextra/i1/2200540853987/O1CN01jaEUas1fK69pJSWAX_!!2200540853987.jpg
---

本人是一个c/c++只懂语法 项目工程化等东西一窍不通的初学者 所以之后的配置或者某些概念可能会写的比较琐碎基础 不足之处请多指教谢谢！

# 0.配置Vs Code环境

此处使用的是WSL

```bash
$ sudo apt-get update && sudo apt-get upgrade
$ sudo apt-get install git build-essential gdb-multiarch qemu-system-misc gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu
```



安装对应的依赖包之后，这里是使用了`xv6-labs-2021`的基础上进行修改

```bash
$ git clone git://g.csail.mit.edu/xv6-labs-2021
```



克隆下来之后，可在命令行中将xv6通过qemu先运行起来，即`make qemu`

正常运行的话会如下

![xv6_init](/./images/xv6_init.png)

可执行`ls cat`等基本命令来测试

程序可使用`ctrl+x,a`来退出 

也可以通过`lsof | grep xv6`查看进程pid然后退出（丑）



回归正题 在vscode中调试需创建`.vscode`文件夹 加入`launch.json`文件

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "debug xv6",
      "type": "cppdbg",
      "request": "launch",
      "program": "${workspaceFolder}/kernel/kernel",
      "args": [],
      "stopAtEntry": true,
      "cwd": "${workspaceFolder}",
      "miDebuggerServerAddress": "localhost:26000",
      // "miDebuggerPath": "/usr/local/bin/riscv64-unknown-elf-gdb",
      "miDebuggerPath": "/usr/bin/gdb-multiarch",
      "environment": [],
      "externalConsole": false,
      "MIMode": "gdb",
      "setupCommands": [
        {
          "description": "pretty printing",
          "text": "-enable-pretty-printing",
          "ignoreFailures": true
        }
      ],
      "logging": {
        // "engineLogging": true,
        // "programOutput": true,
      }
    }
  ]
}
```

以上是我所使用的配置文件 logging中的两个输出是在调试出现错误的时候 可打开的额外配置

注意 `miDebuggerPath`中配置的是调试器的对应路径 这里是使用了`gdb-multiarch` 当然了使用`riscv64-unknown-elf-gdb` 也是可以的



在另一方面 我们需要启动xv6的调试模式 输入`make qemu-gdb`

```bash
chenz@Chenzc:~/xv6-labs-2021$ make qemu-gdb
*** Now run 'gdb' in another window.
qemu-system-riscv64 -machine virt -bios none -kernel kernel/kernel -m 128M -smp 3 -nographic -drive file=fs.img,if=none,format=raw,id=x0 -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0 -S -gdb tcp::26000
```

成功的话 会有如上的反馈 并且可看到在对应的目录下 多了一个`.gdbinit`的文件

这个文件是gdb编译时的文件 把文件里的`target remote 127.0.0.1:26000`行删除或注释

并且在每一次`make clean`之后都需要这么做 目前还没想到好的方法

此外需要比对`make qemu-gdb`之后出现的端口是否和配置文件中注册的端口是一致的 一致才可以正常运行

然后应该就可以在vsCode中调试了

![xv6-debugging](/./images/image-20250111133449101.png)





### *补充

原代码如果想要格式化的话 记得需要创建`.clang-format`文件 设置`SortIncludes: false`

该文件本质上就是项目格式化的配置文件 想要格式化的话一定要设置这个！！！

不然会因为声明顺序不对而导致 某些包没有加载进去

来自一个苦d一小时的初学者。。。



参考：

https://pdos.csail.mit.edu/6.828/2021/tools.html

https://acmicpc.top/2024/02/08/MIT-6.S081-lab0-%E9%85%8D%E7%8E%AF%E5%A2%83/#%E9%85%8D%E7%BD%AEvscode%E5%92%8Cclangd







### *clangd

这玩意是一个程序 用于c/c++代码的格式化 vsCode中有对应的clangd的插件

在WSL中使用需要规定它的路径

![clangdPath](/./images/clangdPath.png)

通过`which clangd`可获得其在PATH中对应的路径 填上即可使用

同时使用的时候 往往都会绑定一个`compile_command.json`文件

可以通过bear拦截Makefile的构建获得该文件 具体命令为`bear -- make qemu`



假如在WSL中使用 并且VSCode右下方出现如这样的通知 

> The '/usr/bin/clangd' language server was not found on your PATH. Would you like to download and install clangd 19.1.2?

这种情况是因为VsCode是在Windows环境下本地打开更新的 可能找不到windows下对应路径的clangd

![remote_explorer](/./images/remoteExplorer.png)

左边通过 **Remote Explorer** 重新打开 对应的路径就ok

从这里打开本质上就是在WSL中内置vsCode并且打开 所对应的路径当然就是WSL中的文件路径了

另外 在WSL的终端中 直接`code`打开也ok
