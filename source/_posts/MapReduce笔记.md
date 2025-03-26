---
title: MapReduce笔记
date: 2025-03-20 16:22:48
tags:
cover: https://img.alicdn.com/imgextra/i4/2200540853987/O1CN01MP0flb1fK69mQKN4W_!!2200540853987.jpg
---

## Introuduction

在分布式系统的日常维护当中 有很多数据在概念上说非常清晰明了的 例如说是爬虫所获得的数据 日志 活跃指标等等 

但是这些数据往往非常大 正因此这些数据往往也是分布式在多台机器上存储的 

当服务请求到来的时候 为了加快请求的速度和效率 往往会进行一个多台机器上并行查询计算的优化

此时 原本清晰明了的查询逻辑 却因为数据量和服务机器的规模而变得冗杂 

而MapReduce正是在这样的分布式场景下的一个答复 他是一个全新的抽象 囊括了并行计算中会出现的**并行化、容错、数据分发、负载均衡**等一系列问题

为分布式系统下的kv查询计算 提供一套简易而强大的使用接口 

也由于他的应用方向是分布式下的场景，所以相比单机场景下，其所做的某些处理可能显得比较冗余。这时候需要考虑并发对这一操作所会带来的影响。

这里所提到的只是一种抽象的设计方法，但是具体的实现还是需要根据具体的业务逻辑进行设计的


## Programming Model

MapReduce的根本思路就是将分布式场景下，所需要对业务逻辑所进行的操作进行再次切分。使其符合原子性，加快分布式并行计算时的效率，从而也不会产生竞态问题

在实际使用该编程模式进行使用的时候，首先会讲这些操作逻辑分解成为Map函数和Reduce函数

这里先摆上相较比较难的定义，然后再举出具体例子解释

### 定义


首先是Map函数，他的定义是

“takes an input pair and produces a set of intermediate key/value pairs.”

将目前已有的kv键值对 安装业务所需分割成为中间态的键值对


然后是Reduce函数，他的定义是

“accepts an intermediate key I and a set of values for that key.
It merges together these values to form a possibly smaller set of values.
Typically just zero or one output value is produced per Reduce invocation.
The intermediate values are supplied to the user’s reduce function via an iterator.
This allows us to handle lists of values that are too large to fit in memory.”

该函数则是将Map函数处理后的中间键值对的数据（以迭代器形式传输）进行统计，然后得出最后的结果


### Example

需求：计算文档集合中每一个单词的出现次数

```rust
map(String key, String value):
    // key: document name
    // value: document contents
    for each word w in value:
        EmitIntermediate(w,"1");
reduce(String key, Iterator values):
    // key: a word
    // values: a list of counts
    int result = 0;
    for each v in values:
        result += ParseInt(v);
    Emit(AsString(result));
```

这里的需求是计数 所以可以设置中间态为计数 通过Map函数将数据的出现频率量化为1 然后通过Reduce函数将所有的1相加起来

简单的例子可能会繁琐化需求实现形式 但是在实际数据量多的前提下 会保证问题的处理效率

### Types

map和reduce函数本质上是一个数据流转的过程 他们在类型上是关联的 有部分类似的地方 有：

````
map (k1,v1) --> list(k2,v2)
reduce (k2,list(v2)) --> list (v2)
````

输入的key和value和输出的key和value分属不同的域。
此外，中间态的key和value和输出的key和value则属于相同的域。

### More Example

此处不做赘述 原理大概是一样的

## Implementation

### Execution Overview

下方是一个具体的MapReduce的使用设计图 将输入的数据分割为M份 使map调用可以在多个机器上调用执行 之后就可以对这些数据进行并行计算

在M函数处理完后 通过一个分区函数将中间态的key进行一类负载均衡的操作（一致性hash） 使得Reduce调用也可以分布式执行

![](https://img.alicdn.com/imgextra/i1/2200540853987/O1CN01E9KAx21fK69omz4Kr_!!2200540853987.png)

类似的 上方所提到的均只是部分思路 详细的设计还是需要根据具体的程序需求来实现

以图中为例可解释具体逻辑如：

内嵌于用户程序中的MapReduce库首先会将输入的文件拆分为M份，每份大小通常为16MB至64MB（具体的大小可以由用户通过可选参数来控制）。
然后便在集群中的一组机器上启动多个程序的副本。

其中一个程序的副本是特殊的-即master。剩下的程序副本都是worker, worker由master来分配任务。
这里有M个map任务和R个reduce任务需要分配。master选择空闲的worker，并且为每一个被选中的worker分配一个map任务或一个reduce任务。

一个被分配了map任务的worker，读取被拆分后的对应输入内容。
从输入的数据中解析出key/value键值对，并将每一个kv对作为参数传递给用户自定义的map函数。
map函数产生的中间态key/value键值对会被缓存在内存之中。

缓存在内存中的kv对会被周期性地写入通过分区函数所划分出的R个磁盘区域内。
这些在本地磁盘上被缓冲的kv对的位置将会被回传给master，master负责将这些位置信息转发给后续执行reduce任务的worker。

当一个负责reduce任务的worker被master通知了这些位置信息(map任务生成的中间态kv对数据所在的磁盘信息)，
该worker通过远过程调用(RPC)从负责map任务的worker机器的本地磁盘中读取被缓存的数据。
当一个负责reduce任务的worker已经读取了所有的中间态数据，将根据中间态kv对的key值进行排序，因此所有拥有相同key值的kv对将会被分组在一起。
需要排序的原因是因为通常很多不同的key(的kv对集合)会被映射到同一个reduce任务中去。如果(需要排序的)中间态的数据量过大，无法完全装进内存时，将会使用外排序。

负责reduce任务的worker迭代所有被排好序的中间态数据，并将所遇到的每一个唯一的key值和其对应的中间态value值集合传递给用户自定义的reduce函数。
reduce函数所产生的输出将会追加在一个该reduce分区内的、最终的输出文件内。

当所有的map任务和reduce任务都完成后，master将唤醒用户程序。此时，调用MapReduce的用户程序(的执行流)将会返回到用户代码中。

*段落对应着图中的数字编号*

大致看下来 与Nginx中的多进程调度和Reactor模型有些类似

数据处理之后 按照这里的设计方法 将会生成R个输出文件存储不同键值对

可以根据具体的业务需求 对这些数据进行不同的后处理 eg 合并作为数据评测集、作为另一个MapReduce调用的输入、进行流处理等等等等

### Master Data Structures

经过上面的描述可以看到它本身并不执行任务 而是一个类似调度者的角色 又或者是像一个消息队列？ 暂时存储中间态的键值对值

综合上述角色可得出 他首先需要存储每一个worker的标识、状态 已经当前进行分片操作之前之后的各个文件 以及他的操作状态（是否进行了处理 —— 未处理 处理中 处理完成）


### Fault Tolerance

容错 分布式系统设计中老生常谈的一个问题 MapReduce的设计理念是极大规模数据大处理 所以他必须能够具有一定的容错能力

#### Worker Failure

**master节点会周期性的ping每一个工作节点 通过心跳机制 判断当前的从节点是否在正常工作**

也是老生常谈的纠错机制 许多的配置中心与中间件的集群判活 都是通过这一机制进行实现的 例如最典型的**Redis的哨兵机制**

说回来 假如发现某个节点挂了 或者是发生了故障 需要有这个能力 将分配给他的这些任务进行重新分配

”任何在这个有故障的worker上处理中的map或reduce任务状态也将被重置为初始化，并且(这些被重置的任务)能够被重新调度执行“

面向上文所说的结构而论时 已完成的map任务在故障发生时 也需要被重复执行

因为完成了map任务的数据时存储在对应机器的本地磁盘当中 而当机器发生了故障 这个已经处理完成的数据集存在可能会被污染或者是丢失 所以此时需要重新执行该任务

而已经完成的reduce任务则不需要重新执行 因为按照上方的设计 当他处理完成 是会被输出到一个中心化的全局文件系统的当中的

#### Master Failure

同样也是老生常谈的一个容错问题 同样可以类比Redis中备份机制

Redis中为了防止突然崩溃 数据丢失 他提供了两个备份的方法 RDB和AOF

这里则是借鉴了RDB的形式 定时对master机器中的数据处理状况进行备份

而正如上方所说的 master节点中记录了当前的MapReduce任务的所有执行状况

当master节点发生错误的时候 只需要读取比较新的节点 重启当前机器就可以了

这样保证了数据的逻辑一致性 相当于回滚了一段时间内MapReduce的计算


#### Semantics in the Presence of Failures

面对故障时的语义

当用户提供的map和reduce算子都是机遇输入的确定性函数时，所实现的分布式计算后输出与整个程序串行执行后得到的结果是一样的

人话就是 应当保证他是可重排的 ———— 并行和串行的执行不会导致程序最后的结果不一致

这一特点是由 分割解耦而成的map和reduce的原子性提交机制来实现的

不同的处理后文件之间也通过机制保证了不会杂糅在一起

例如说 当一个reduce任务完成了，执行他的worker会将其重命名为最终的输出文件 然后可能会在某个时间窗口之间对所有的输出文件进行合并

在这个过程中 假如说这个最终重命名的机制是通过时间保证的 同一时间内就会产生多个重命名的相同文件 面对这样的问题 操作系统提供了**原子性重命名**操作保证这些数据文件之间的唯一性

在这个问题上 是通过以下保证了整个运行流程的唯一性：

**map确定性 + 数据临时存储、流转的确定性 + reduce函数 + 数据存储的确定性**

通过以上几个行为 一并保证了 整个数据处理过程**串行和并行前提下的执行结果是一致的** 此时被称为**MapReduce的强语义**

而一旦缺失了这里其中某一部分的确定性 就会导致这种一致性被打破 此时被称为**弱语义**


### Locality
局部性  （!= 局限性）

这个需要稍微理解一下 本质意思就是在存储计算数据的时候 MapReduce通过多种措施来节约网络带宽

首先 输入的数据是被存储在组成集群的机器本身的磁盘上 并且每份数据为了容错避免丢失等场景 我们都会为他设计多个副本（3） 每个副本存在不同的机器上

在我们的master节点调度任务的时候 他会同时考虑**数据与worker**节点之间的相对存储位置。

尽量保证 **存储了数据副本的机器上执行对应的map任务** 如果没有对应的机器 就尽量保证**执行任务的机器靠近数据所在的机器**

这就保证了绝大多数的输入数据都是从本地读取 或者是近距离读取 而不会消耗很多的网络带宽


### Task Granularity
任务粒度

所谓任务粒度指的是 如何将这个大任务分治成小任务并行计算 分治到多大的一个层次 分治到多少份

在理想情况下 所设置的map任务对应的数量M reduce任务对应的数量R都应该是 **远大于worker数量的**

why？

首先将任务细粒度化 可以更好的实现**负载均衡** 每个硬件的可负载能力不同的前提下 可以按照对应的能力动态分配数量不同的任务

然后 可以更好实现**故障恢复** 按照上方的思路 任务失败或map任务完成 机器故障的时候 都需要重新运行对应的任务 而细粒度任务 另一方面上提高了任务的成功率（执行时间短）

还有一个重点即为 充分利用当前的分布式并行计算资源————多线程同理

另外 上方所提到的**局部性** 减小网络io传输的成本 也是很重要的一点

但是在实际上 假如还需要对mapReduce执行后的数据进行处理的话 还需要考虑一些例如合文件、去重等等问题 此时如果R的数量远大于worker的话 本身这个文件io等操作带来的成本就很高 并且文件太小的话 也无法充分利用局部性所带来的优化 于是只需要设置**R的大小为我们预期使用worker机器数量的小几倍**即可

原文中给出的实践是 将独立任务的大小控制在16mb-64mb之间 将map阶段的任务设置为远大于worker数量 reduce阶段的数量大于worker 小于机器

原文给出其例子是：

-- We often perform MapReduce computations with M = 200,000 and R = 5,000, using 2,000 worker machines.

-- 我们执行MapReduce计算时，通常使用2000台worker机器，并设置M的值为200000，R的值为5000。

## Backup Tasks

这里主要描述的是 在分布式实际运行的过程中 都会存在一个“落伍者”的问题————由于其他任务&网络&CPU等种种问题导致运行效率大幅减慢的机器

面对这个问题 MapReduce的设计是 当某个运算还差落伍者没有完成的时候 此时会将剩余的任务进行备份 然后master节点会查找空闲worker节点 并且使空闲worker节点执行任务的副本

这整个过程称为 **“后备执行”**

而这些剩余的任务无论是本身执行完成还是副本完成 都会标记已完成

原文称为 明显较少了大型MapReduce操作的完成时间

本质上更加活用一波当前的空闲机器资源


## Refinements
改进

### Partitioning Function
分区函数

MapReduce中目前的实现是通过**哈希取模** 将任务均匀的分到每个机器上

根据具体的业务情景 这里的分区函数可以进行自定义 使更好的符合场景

原文例子是 假如map任务输出的中间态键值对key为url 而需求是将统一主机上的所有url写入同一文件当中 就可以之间在取模的时候 使用`hash(Hostname(urlkey))` 直接将对应的key分道同一个机器或临近的多个机器上 这样子就不需要后续的文件聚合或、减小它所带来的成本洗哦啊好了

### Ordering Guarantees
有序保证

保证在对任务进行处理的时候 中间态的键值对排序是按照**key值递增的顺序处理的** 对之后的数据查找 定位效率都很有帮助

### Combiner Function
组合器函数

这个本质上有点像是的流处理转为批处理的 但是MapReduce处本身就是批处理 所以称为流处理也不太准确

意思就是在数据已经执行完map函数 暂存在机器本地磁盘 收到了reduce的拉取请求 发送数据之前 

**制定一个类似滑动窗口 将这个滑动窗口内的数据进行一次汇总之后 再将其进行发送**

当然这个窗口也会有诸如大小 最长存活时间之类的限制 在这里被称为Combiner 组合器函数

这个合并的逻辑本身就是一种数据的预处理 **所以通常情况下 该函数的逻辑和reduce的实现是相同的**

### Input and Output Types
输入和输出的类型

此库为多种不同格式输入数据的读取提供了支持 提供了统一实现的接口

用户可以自定义是心啊这个reader接口 来获取多种不同格式的输出数据

### Side-effects
副作用

MapReduce的实现并没有考虑原子性并发性等东西 *个人觉得按照它的设计思路 只是一种分治问题的设计思路 就应该将其极简化保证效率的最高 所谓的并发安全这些应该由使用者自己去思考 将问题原子化 或者在这个基础上加上条件变量之类的*

原文有：

> We do not provide support for atomic two-phase commits of multiple output files produced by a single task.
> Therefore, tasks that produce multiple output files with cross-file consistency requirements should be deterministic.
> This restriction has never been an issue in practice.

> 我们没有为单个任务生成多个文件的场景提供原子性二阶段提交的支持。
> 因此，会生成多个输出文件且具有跨文件一致性需求的任务应该是确定性的（任务是确定性函数算子）。
> 在我们的实践中，这一限制并没有带来什么问题。

### Skipping Bad Records

有时候可能会存在bug导致 MapReduce处理数据的时候会报错 此时提供了一个配置上直接将其忽略掉 直接向前推进

具体的实现是 通过捕获信号 定位错误发生的位置 并且在错误再次发生的时候 跳过该记录

> Each worker process installs a signal handler that catches segmentation violations and bus errors.
> Before invoking a user Map or Reduce operation, the MapReduce library stores the sequence number of the argument in a global variable.
> If the user code generates a signal, the signal handler sends a “last gasp” UDP packet that contains the sequence number to the MapReduce master.
> When the master has seen more than one failure on a particular record, it indicates that the record should be skipped when it issues the next re-execution of the corresponding Map or Reduce task.
> 每个worker进程都安装了一个信号处理器，用于捕获段异常(segmentation violations)和总线错误(bus errors)。
> 在调用用户的Map或Reduce操作前，MapReduce库会将参数的序列号存储在一个全局变量中。
> 如果用户代码产生了一个信号，则信号处理器将会向MapReduce的master发送一个包含了(该参数)序列号的"最后喘息(last gasp)"UDP包。
> 当master一个特定的记录不止一次的导致故障时，master会指示对应的Map或Reduce任务在下一次重新执行时应该跳过该记录。

### Local Execution

这个没什么好说的 开发者针对MapReduce的调试和测试开发了一个在本地就可以进行测试的demo 可以通过gdb等工具对他进行测试

### Status Information

master机器存储维护了在MapReduce进程中的关键信息 而开发者开发了一个dashbord 可以通过这里获取当前实时运行时的状态信息

### Counters

MapReduce提供计数器相关函数实现 可以通过它对当前的运行状况 做一个自定义的统计是实现

## Performance

这一节说的是实际的运行效果

使用了分布式Grep Sort为例子

并且描述了一些产生了异常时 Skipping机制的影响效果与后备任务对排序所带来的优化

## Experience

### Large-Scale Indexing

Google中采用MapReduce重写了web search时的索引 对整个模块都带来了优化

- 降低代码行数 专注于具体的业务（处理容错 分布式等细节都在MapReduce库的内部）

- MapReduce库性能好 -> 不需要存太多的冗余数据保存洗哦啊率 -> 将概念无关的计算进行拆分 -> 减小存储压力、避免额外数据传输

- 更易操作 （库内部包含了机器故障 执行 网络断开）时的一些兜底措施 运维难度降低

- 水平拓展 加机器轻松提性能

## Related Work & Conclusions

横向比较及总结


## 完

这里所提到的横向比较第三方系统 都不太熟悉 以及对实际例子产生的一些优化没有一些比较实际的概念 

发现在系统设计这一块的思路有些形而上了。。停留在理论、纸上谈兵一类。。


谢谢哥的翻译 链接🈶:

https://www.cnblogs.com/xiaoxiongcanguan/p/16724085.html#info