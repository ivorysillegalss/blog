---
title: mit6.s081 lab4
date: 2025-02-02 00:53:20
tags: mit6.s081
---

### RISC-V assembly

这个lab是回答一下问题并记录 此处就直接把问题分析和答案打上来了 答案通过chatGPT查验

`call.asm`中的`g`、`f`、`main`具体的代码

```asm
int g(int x) {
   0:	1141                	addi	sp,sp,-16
   2:	e422                	sd	s0,8(sp)
   4:	0800                	addi	s0,sp,16
  return x+3;
}
   6:	250d                	addiw	a0,a0,3
   8:	6422                	ld	s0,8(sp)
   a:	0141                	addi	sp,sp,16
   c:	8082                	ret

000000000000000e <f>:

int f(int x) {
   e:	1141                	addi	sp,sp,-16
  10:	e422                	sd	s0,8(sp)
  12:	0800                	addi	s0,sp,16
  return g(x);
}
  14:	250d                	addiw	a0,a0,3
  16:	6422                	ld	s0,8(sp)
  18:	0141                	addi	sp,sp,16
  1a:	8082                	ret

000000000000001c <main>:

void main(void) {
  1c:	1141                	addi	sp,sp,-16
  1e:	e406                	sd	ra,8(sp)
  20:	e022                	sd	s0,0(sp)
  22:	0800                	addi	s0,sp,16
  printf("%d %d\n", f(8)+1, 13);
  24:	4635                	li	a2,13
  26:	45b1                	li	a1,12
  28:	00001517          	auipc	a0,0x1
  2c:	80850513          	addi	a0,a0,-2040 # 830 <malloc+0xec>
  30:	00000097          	auipc	ra,0x0
  34:	65c080e7          	jalr	1628(ra) # 68c <printf>
  exit(0);
  38:	4501                	li	a0,0
  3a:	00000097          	auipc	ra,0x0
  3e:	2b8080e7          	jalr	696(ra) # 2f2 <exit>
```

这里涉及到的很多代码可以粗略理解为三个层次

**准备现场 -> 函数调用、执行逻辑 -> 恢复现场**



**准备现场如何做？** 此处以`g`函数为例子

```asm
addi	sp,sp,-16
sd	s0,8(sp)
addi	s0,sp,16
```

这里首先是通过移动SP栈指针 分配了16字节的空间

然后将s0寄存器中值保存到刚刚分配到的空间的基础上 偏移量为8的位置

然后修改s0寄存器中的值 让它之上当前分配的栈的栈顶

```asm
   6:	250d                	addiw	a0,a0,3
```

真正执行计算 RISC-V中 函数传入的值一般都是放在`a0`寄存器当中的 如果不够放的话 依次会放到`a1`、`a2`等寄存器当中

返回值则会放到`a0`寄存器当中

这应该算是RISC-V中约定俗成的一种规范吧

```asm
   8:	6422                	ld	s0,8(sp)
   a:	0141                	addi	sp,sp,16
   c:	8082                	ret
```

这里就是恢复现场并且`ret`跳转的代码了

将从sp中偏移量为8 之前准备现场时保护的值拿出来 重新放回到s0当中

然后重新修改栈指针 回收该函数所使用的空间

最后ret跳转 （具体地址一般在外部跳转这个函数的时候 外部进行设置好 所以这里不用设置）



可以看到`f`函数是直接`return g(x)` 但是汇编中是因为编译器经过了内联优化

没有进行跳转 而是直接将`g`函数中的代码复制了过来

所以这里不再作解释



对于`main`函数 也可以用这种思路进行思考

```asm
  1c:	1141                	addi	sp,sp,-16
  1e:	e406                	sd	ra,8(sp)
  20:	e022                	sd	s0,0(sp)
  22:	0800                	addi	s0,sp,16
```

由于`main`函数是主函数 所以需要同时设置返回时跳转的地址 即保存在`ra`寄存器当中

​	

```asm
  24:	4635                	li	a2,13
  26:	45b1                	li	a1,12
  28:	00001517          	auipc	a0,0x1
  2c:	80850513          	addi	a0,a0,-2040 # 830 <malloc+0xec>
  30:	00000097          	auipc	ra,0x0
  34:	65c080e7          	jalr	1628(ra) # 68c <printf>
```

这里就是将数据进行处理了

对照一下原来的c代码可以发现这里是直接将`f(8)`的值计算了出来 和`13`一起放进了寄存器中 等待调用

这个也是编译器优化的锅 他将`f(8)`这一函数调用的过程省略了 是 **常量折叠**的体现 直接将其中的值由编译器计算出并且代入



要注意调用printf的过程本质上也是一次函数调用 

所以也是需要准备现场的 这里体现在将计算参数放入寄存器当中

通过指针运算 计算出`printf()`函数的实际位置

最后进行跳转



```asm
  38:	4501                	li	a0,0
  3a:	00000097          	auipc	ra,0x0
  3e:	2b8080e7          	jalr	696(ra) # 2f2 <exit>
```

这一个阶段下 是计算已经完成了

由于`printf`或者其他函数调用的返回值都是会存在寄存器`a0`当中的

所以此处需要将他置0 恢复一开始的现场

然后再对指针进行计算 计算出`ret`所跳转的地址

 （此情境下 是从`printf()`函数内部跳转回`main()`函数当中）

跳转回来了 直接执行最后的`exit(0)`指令 跳转到`exit`对应的位置



至此 调用结束



理解了整个流程之后 就很好回答lab上的问题了

1. 

Q: **Which registers contain arguments to functions? For example, which register holds 13 in main's call to `printf`?**
哪些寄存器包含函数的参数？例如，主函数调用 `printf` 时，哪个寄存器保存了 13？

A: 包含参数的寄存器有`a0`、`a1`、`a2`等等... 这里调用`printf`的时候 是`a2`保存了13

```asm
  24:	4635                	li	a2,13
```

2. 

Q: **Where is the call to function `f` in the assembly code for main? Where is the call to `g`? (Hint: the compiler may inline functions.)**
在主程序的汇编代码中，调用函数 `f` 在哪里？调用 `g` 在哪里？（提示：编译器可能会内联函数。）

A: 调用函数按理来说是会在45 47行中间 但是此处编译器优化进行了常量折叠。理论上是在这一块会进行两次嵌套的分配栈空间 依次到`f`、`g`函数中对值进行计算，再依次恢复



3. 

Q: **At what address is the function `printf` located?**
函数 `printf` 位于哪个地址？

A: 在这里 `printf()`具体的地址计算过程是：先将`PC`寄存器和`0x1`进行计算 得出的值存到`a0`当中 然后将`a0`的值减去2040所得到的

**也就是说  它的位置并不是固定的 是通过计算从而动态确定的**



4. 

Q: **What value is in the register `ra` just after the `jalr` to `printf` in `main`?**
在 `main` 中， `jalr` 到 `printf` 之后，寄存器 `ra` 中的值是什么？

A: 上方也已经解释过 跳转到`printf`的过程本质上也是一次调用 同样需要准备现场等步骤 而在执行完毕之后 是会跳转到当前`main`函数下 `jalr`的下一条指令



5. 

*TODO 这玩意半夜有点看不懂*

**Run the following code.**
运行以下代码。

```
	unsigned int i = 0x00646c72;
	printf("H%x Wo%s", 57616, &i);
```

**What is the output? [Here's an ASCII table](http://web.cs.mun.ca/~michael/c/ascii-table.html) that maps bytes to characters.**
这是什么输出？这是一个 ASCII 表，它将字节映射到字符。

**The output depends on that fact that the RISC-V is little-endian. If the RISC-V were instead big-endian what would you set `i` to in order to yield the same output? Would you need to change `57616` to a different value?**
输出取决于 RISC-V 是小端的这个事实。如果 RISC-V 是大端的，你会将 `i` 设置为什么值以产生相同的输出？你需要将 `57616` 改为不同的值吗？

**[Here's a description of little- and big-endian](http://www.webopedia.com/TERM/b/big_endian.html) and [a more whimsical description](http://www.networksorcery.com/enp/ien/ien137.txt).**
这是对小端和大端的描述，以及一个更富有想象力的描述。
