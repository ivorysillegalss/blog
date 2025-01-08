---
title: autoMQ
date: 2025-01-08 16:34:20
tags: interview
---

两面项目面：
time: 2025.1.3

介绍筋斗云项目与对消息推送项目中部分业务内容进行现场修改

## 筋斗云

### ipconfig模块相关

#### ipconfig是什么？做了什么？

它是一个我自己设计的服务发现模块。他会读取配置文件中的服务配置，并且以etcd作为数据源。通过etcd的watch机制，实时监听业务前缀下服务状态信息的更改。返回当前的最优列表。并且暴露出对应的http接口可以让Nginx进行获取。



#### 数据是从exporter中获取的？这个模块有什么用？

这个模块所起到的作用主要是数据拉取和分析。他会从业务模块中通过gRPC+protobuf获取到对应的业务状态指标信息，例如说是当前的CPU内存，硬件资源，与请求数量和请求平均耗时等程序运行时指标。

当获取到这些指标之后，exporter会将这些信息put到etcd中。而ipconfig会通过etcd的watch监听机制立马得知。同时会将这些信息转换为http的格式，并且供以普罗米修斯进行拉取（监控模块）。



#### 介绍一下OpenResty

本质上是Nginx的增强。Nginx主要的作用是反向代理和Web服务器等。并没有其他更为复杂的功能，而OpenResty便是Nginx在这一维度上的一个拓展。



#### 如何实现ipconfig模块和Nginx之间的互动

主要是通过OpenResty中的定时机制和lua脚本实现热更新。

我的ipconfig模块中暴露了一个http接口。当请求这个接口的时候，可以获取到目前最优的服务列表。

在Nginx这一层面上。对于请求服务的路径，我们不会将他写死为对应某个服务的列表。而是将他写为读取Nginx中的共享内存。

所以实现的重点就在于如何更新这一个共享内存。我使用了OpenResty中的定时任务机制，这个定时任务会执行一个lua脚本。该lua脚本则会请求ipconfig服务器上的对应请求。从而更新缓存中的服务列表。

综合的来说就是。通过Nginx+的定时任务实现最优服务列表的更新，并将值更新到内存当中。请求到来的时候，就会直接读取该共享内存中的值。保证了服务列表的最优性和实时性吧。



#### 假如此时不巧由于网络波动的一瞬间，service_list[1]中的服务宕机了，这时候怎么办？

按照当前的设计的话，就只能等待下一次共享内存更新的时候，从其中获取更新后的服务列表。



#### 假如此时的Ipconfig模块宕机了，该怎么办

没宕机的情况下是访问服务列表中的最优服务。若宕机了，lua脚本请求的时候就会错误。此时我会根据上一次访问得到的最优列表，为每一个服务都定义一个兜底的权重。而当请求到来的时候，会在这个权重计算的基础上，再对各服务进行随机选择。这便是一种兜底策略。



#### 服务发现模块依赖的数据源是？为什么？

使用的是etcd，主要原因是当前的规模并不算大。属于用户量较小，压力较小的分布式场景。大部分情况下都是可以保证可用性。而根据CAP理论的话，我们可以偏向于使用一致性较强的中间件。而etcd由于是通过Raft协议实现的，保证了它的一个强CP。所以选择了etcd来兼顾一致性和可用性。



#### 有什么坏处吗这个方案？

因为etcd终究是属于CP模式的，所以高低会造成一点网络的延迟。兴盛一部分的可用性。但是这一部分的话，也可以通过缓存和配置调优的再度进行优化。



#### 如何得出当前的最优列表的？（具体的负载均衡算法是？）

当前的方案是以时间为颗粒度。我会针对每一个服务维护一个滑动窗口。这个滑动窗口则是最近的N个时间节点中的各个服务中的状态信息。然后当我需要获取这个最优列表的时候，我会给不同时间刻度的窗口以不同的权重。并且根据他们的这些权重和状态信息的指标所计算出一个加权平均。这个计算的颗粒度首先是以G为单位的，这是因为单位过小的话，对程序的运行没有太大的参考价值。



#### 这个算法求最终分数与遍历排序的过程会带来一定的时间延迟，怎么优化？

时间成本主要是来源于排序和计算。而计算的成本主要是遍历这个滑动窗口的时间复杂度。

具体的话，我们可以将当前时刻的所有窗口，先求出一个加权平均值。再根据这个值进行计算就可以了。减少了遍历次数。



#### 当前的这个算法，你怎么证明他是最优的？

目前的算法并不是最优的，目前的算法只是我在采集了常见的状态指标信息之后，通过线性回归计算出的一个方案。而具体涉及到的最优，需要结合服务部署的地点和其他各种因素。需要算法工程师来进行优化。



#### 它可以解决未来可能会出现的一些网络波动的情况吗？有什么优化的思路吗？

不可以，我的算法本质上是一个基于时间刻度的，基于服务过去的状态信息所计算的一个平均值的一个方案。根据过去的状态信息，是无法预测未来将要出现的网络波动的。但是我目前有一个优化的思路，可以利用etcd的watch机制，再出现网络波动的时候，更改负载均衡的策略。不使用原来的算法，而是监控系统获得到的信息，通过人工来进行调控权重，然后再根据人工所调控的这一个权重来进行一个一致性哈希或者其他的二次处理。



### SSE & 流信息推送相关

#### SSE是什么？和WebSocket有什么区别？

SSE基于http协议，本质上是一种non-blocking的模式，只需要修改对应的请求头即可使用。WebSocket则需要升级协议才可以使用。

这也造成了WebSocket相比之下会比较中，SSE则比较轻量化。

SSE支持断线重连，WebSocket则需要自己实现这一模块。

SSE是单向通信，只能从服务端推送消息到客户端当中。WebSocket是全双工双向通信。

而对于这一场景来说。我作为服务端只需要将收到的消息推送给客户端即可，这一过程中不需要客户端做任何特殊响应，仅需要在消息传输后客户端返回ACK即可。



#### 如何使用SSE？

设置对应的服务器响应头就可以了

```
Content-Type: text/event-stream
Cache-Control: no-cache
Conection: keep-alive
```

本质上就是确保维持一个长连接，为了这个长连接不是收到缓存消息，设置为no-cache。同时信息是以流的形式发过来的，所以设置为text/event-stream



#### 你提到了使用结合SSE和MQ实现异步返回ACK工作，整个工作的流程是？

单次访问一共分为三个请求：

1. **握手预备**：这个请求的流程是，后端一旦接收到会根据收到的内容组装一个请求，并且异步提交调用api的任务。然后返回给前端一个ACK。标识消息调用请求发起成功。在这个过程中，会有指定的模块消费MQ中的内容，接受并对第三方模型发起调用的请求，将获取到的流信息以列表的格式存储在结构体当中。
2. **获取流信息内容**：前端在收到第一个请求的ACK之后，会再度发起另外一个post请求，这个请求中只包含用户的token。当后端收到这个请求的时候，他会从存储流信息的结构体当中，拿出这一些对应的信息。并且再次以SSE流形式发送给前端。
3. 在传输的这一个过程中，前端是会一直接受流信息。直至SSE中发出一个stop的信令。标识当前流信息的终止。或者如果出现了错误的话，同样是可以通过SSE自带的onError()方法来进行捕获的。
4. 说回来，前端收到stop的时候，标识当前的流信息已经收到了。但是后端不知道这一事实，所以就有了第三次请求。第三次请求中，主要是告诉后端，前端已经无误收到当次流信息了。然后后端就可以进行空间回收，历史记录存储等后置工作。

通过以上三次的请求，就实现了一次流信息的下发。



#### 那这种使用SSE的形式会不会导致收到的流信息乱序呢？

不会，因为SSE是基于Http实现的，而Http是基于TCP实现的。在TCP中已经通过滑动窗口和ACK等一系列机制保证了消息传输过来时的有序性和可靠性。所以基于TCP的SSE就不会出现乱序这一问题。



#### 假如这个过程中 前端没有收到消息 发起后续的连接怎么办

假如是第一次的后端响应前端没有收到。前端就不会发起第二次连接（处于等待状态）。后端中即使调用了模型收到了对应的结果，如果没有从结构体中获取，会通过定时任务自动销毁。而前端会直接丢弃掉这一次的任务。

假如是第二次的流信息响应没有收到的话，流程和后果也是一样的，都将该次的流信息丢弃，将本次请求标记为失败。

假如第三次没有成功收到信息的话。消息是正常发到前端了，但是后端不知道。这一种前提下对前端用户体验没有什么大的影响。后端则会回收掉这一次消息。上下文情境下可能有些许的错误，因为没有将该次的流信息存储起来。作为当前的情境下，我认为单次流信息的消息价值是比较低的，所以这种情况所带来的影响较小，没有作额外处理。



#### 什么叫做通过CAS和时间戳解决多批次流信息间的竞态问题

我们这里将访问一次流式API得到的所有流信息称为一批流信息，多次访问所得到的不同多个信息则称为多批流信息。

我这里设计一个map[string]结构体去存储，这个结构体中主要包含的是当前的流信息，与当前的流信息所对应的时间戳版本号。

当消费层得到访问三方API的流信息时，会先经过这个handler，这个handler将信息存储到map当中。前端发起获取流信息内容的时候，本质上就是从这个map当中去获取的。

这个map本质上是一个以用户为细粒度的。对于单个用户当流信息到来的时候，他会将消息相关内容存在map对应用户的结构体中。

竞态问题的产生主要是因为用户细粒度的原因。假如一个用户他在短时间内，访问了多次大模型。这时候就会造成**批次间流信息的竞态问题**。

我的处理方式就是，对于每一批流信息都加上当前的时间戳作为版本号，假如同一时刻两个版本的流信息都到来了的话，这时候就会以新版本的为主。丢弃旧版本的信息。



#### 那如何理解这一块所说到的回收复用管道资源呢？

这里的意思就是，在我的存储结构体中，对应的流信息，在正常的情况下，要么会推送到前端，要么会通过定时任务丢弃。但是在我们日常使用到大语言模型的情境下，我们有一定几率会在短时间内进行多次提问（对一次chat所得到的response不满意）。

而这多次提问，在普通的情况下会不断的申请空间并且销毁。这一成本是随着活跃用户的数量增长的。我这里的设计是采用了一个时间轮的算法，当一个用户完成单次访问的时候，会让他过了一段时间再回收空间。假如在这段时间内，再次有访问到来的时候，就可以复用这个空间，并且会刷新定时任务的回收时间。

这个定时任务是采用了时间轮的算法来执行，这个算法在情境下的话，会造成一定的时间损耗，但是并不影响实际的回收运行。同时会使任务的定时处理相比于优先队列等更加高效。


---


## 消息推送

#### 责任链模式下发MQ任务`SendMqTask`类中，增加消息下发重试功能

修改前：

```java
    @Override
    public void execute(TaskContext<SendContextData> taskContext) {
//        从上下文中取出数据 序列化包装发送
        List<TaskInfo> taskInfos = taskContext.getBusinessContextData().getTaskInfos();
        String jsonTaskInfos = JSON.toJSONString(taskInfos, SerializerFeature.WriteClassName);
//        下发信息 具体下发逻辑封装在support对应包中
        try {
            sendMqService.send(topicId, jsonTaskInfos, tagId);
        } catch (Exception e) {
            taskContext.setException(Boolean.TRUE).setResponse(TaskContextResponse.<SendContextData>builder()
                    .code(RespEnums.SEND_MQ_ERROR.getCode()).build());
        }
//        成功下发信息
        taskContext.setResponse(TaskContextResponse.<SendContextData>builder()
                .code(RespEnums.SEND_MSG_MQ_SUCCESS.getCode()).build());
    }
}
```

修改后：

```java
    @Override
    public void execute(TaskContext<SendContextData> taskContext) {
//        从上下文中取出数据 序列化包装发送
        List<TaskInfo> taskInfos = taskContext.getBusinessContextData().getTaskInfos();
        String jsonTaskInfos = JSON.toJSONString(taskInfos, SerializerFeature.WriteClassName);
//        下发信息 具体下发逻辑封装在support对应包中

        Integer failTimes = 0;
        Integer maxRetry = 3;
        while (failTimes < maxRetry) {
            try {
                sendMqService.send(topicId, jsonTaskInfos, tagId);
                break;
            } catch (Exception e) {
                failTimes++;
            }
        }
        if (failTimes.equals(maxRetry)) {
            taskContext.setException(Boolean.TRUE).setResponse(TaskContextResponse.<SendContextData>builder()
                    .code(RespEnums.SEND_MQ_ERROR.getCode()).build());
        }


//        成功下发信息
        taskContext.setResponse(TaskContextResponse.<SendContextData>builder()
                .code(RespEnums.SEND_MSG_MQ_SUCCESS.getCode()).build());
    }
}
```

#### 责任链中节点出现异常的时候是怎么处理的？

出现异常时，节点内组装异常结构体并返回，直接交给外部处理

**TaskController.class**
```java
    public TaskContext<TaskContextData> executeChain(TaskContext<TaskContextData> taskContext) {
        TaskTemplate taskTemplate = taskTemplates.get(taskContext.getBusinessCode());
        List<TaskNodeModel> taskList = taskTemplate.get();
        for (TaskNodeModel task : taskList) {
//            TODO
            task.execute(taskContext);
            if (taskContext.getException()) {
                return taskContext;
            }
        }
        return taskContext;
    }
```
**Service.class**
```java
//        责任链执行任务
        TaskContext<TaskContextData> taskContext = taskController.executeChain(sendContext);
//        构造SendResponse返回响应结果
        return SendResponse.builder().code(taskContext.getResponse().getCode()).build();

```
