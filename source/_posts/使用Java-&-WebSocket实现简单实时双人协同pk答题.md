---
title: 使用Java & WebSocket实现简单实时双人协同pk答题
date: 2024-03-10 16:28:39
tags: Java
---

## 引入

🚀 **引入与技术选型**： 在实时互动应用中，实现流畅的多人协同对战功能是一大挑战。WebSocket技术，以其全双工通信能力，提供了解决方案。不同于传统HTTP请求的短连接，WebSocket建立持久连接，极大减少了通信延迟，为实时数据传输提供了理想的环境，极大减少了传统HTTP轮询的延迟，为实时游戏提供了必要的技术基础。

💡 **架构设计**： 采用前后端分离，将WebSocket服务独立部署。前端使用JavaScript建立与WebSocket服务器的连接，实现即时消息交换；后端则负责逻辑处理，包括玩家匹配、状态同步等，使用Java语言，借助Spring框架的强大支持，构建了稳定的WebSocket服务。

🔧 **技术细节**：

-   **状态同步**：在对战中，通过WebSocket实时同步玩家的操作和游戏状态，每个动作都通过服务器广播给所有参与者，确保了游戏进程的同步性和准确性。

<!---->

-   **异常处理与稳定性**：对于WebSocket连接。一旦检测到游戏中的某一方异常断开，系统会自动结算对局。
-   **用户状态设置**：用户的状态可粗略分为匹配中，对局中等，不同的状态
-   **用户匹配机制**：项目中的匹配系统采用动态队列，遵循先来后到，并可以根据用户的段位等信息进行分开匹配，一定程度上提升用户体验。
-   **并发错误避免**：在项目中，每一次对局的双方用户的状态信息都将保存在一个hashmap当中，实现一个房间的机制，标记用户的状态为游戏中，防止第三用户加入对局，引发未知错误。

🏷️ **实现过程：**

整个对战大致可以分为三个部分：对战前，对战中，对战后。

对战前：匹配对手，匹配成功后，服务器获取双方的个人信息，以及单次对局中的题目列表，发送到双方的客户端中。

对战中：双方用户答题，提交答案后。客户端将答题信息发送到服务器中，服务器将其广播到对方客户端中。刷新双方分数信息。之后的每一次答题均重复其过程。

对战后：答题完毕，刷新用户为结算状态。服务器根据双方得分情况判断胜负，广播到双方客户端中。


**此篇先介绍后端相关**


## 一、WebSocket 后端

位于ws包中

### 1、实体类

#### (1). 通信信息类 `ChatMessage<T>`

```
@Data
public class ChatMessage<T> {
    /**
     * 消息类型
     */
    private MessageTypeEnum type;
    /**
     * 消息发送者
     */
    private String sender;
    /**
     * 消息接收者
     */
    private Set<String> receivers;
    
    private T data;
}
```

**MessageTypeEnum** : 指此通信信息的类型 即pk中每一个阶段的不同信息类型 eg匹配中 详见下文

**sender** : 指此通信信息的发出方 这些响应信息是由谁来发出的

**Set<Sting> receivers** : 指此通信信息的接收方 这些信息是由谁来接受 这个谁可以是单个人也可以是一群人

**T data** : 指此信息中包含的实际数据 由 **MessageTypeEnum** 来确认信息的类型，**data** 表示信息的数据

#### (2). 消息类型枚举类 `MessageTypeEnum`

```
/**
 * 消息类型
​
 */
public enum MessageTypeEnum {
    /**
     * 匹配对手
     */
    MATCH_USER,
    /**
     * 游戏开始
     */
    PLAY_GAME,
    /**
     * 游戏结束
     */
    GAME_OVER,
}
```

此枚举类的三个信息分别代表在游戏的不同阶段中，三个不同的状态（不同的状态下发出不同的信息）

#### (3). 回答情况 `AnswerSituation`

```
@Data
@AllArgsConstructor
@NoArgsConstructor
@Component
public class AnswerSituation {
    private ArrayList<String> selfAnswerSituations;
}
```

此实体类代表着用户pk答题的情况 每一个用户 在每一局游戏中 每一个用户 都会有一个自己的 **AnswerSituation**

#### (4). 单局游戏回答情况 `RoomAnswerSituation`

```
@Data
@AllArgsConstructor
@NoArgsConstructor
public class RoomAnswerSituation {
    private String userId;
    private String receiver;
    private AnswerSituation selfAnswerSituations;
    private AnswerSituation opponentAnswerSituations;
}
```

其中一种响应信息的类型 **(GAME_OVER)** 所对应的**T data**数据，包含每一局游戏中双方的回答情况，以及对方和自己的id标识（便于前端判断）

#### (5). 用户的信息 `UserMatchInfo`

```
@Data
public class UserMatchInfo {
    private String userId;
    private Integer score;
}
```

包含用户的id及分数 在响应信息类型为 **(TO_PLAY)** 时 传输对方用户以及自己的分数信息

在响应信息类型为 **(MATCH_USER)** 时 初始化双方的分数（总分）及id信息

#### (6). 游戏对局信息 **`GameMatchInfo`**

```
@Data
public class GameMatchInfo {
    // TODO UserMatchInfo 后期按需扩充dan等属性
    private UserMatchInfo selfInfo;
    private UserMatchInfo opponentInfo;
    private List<Question> questions;
//    用户名
    private String selfUsername;
    private String opponentUsername;
//    头像
    private String selfPicAvatar;
    private String opponentPicAvatar;
}
```

在匹配到对手之后 发送的**chatMessage**中的 **T data** 数据类型

包含在这一轮游戏中 自己以及对方的数据信息

此处包含**双方 id 用户名 头像 问题** 以及初始化后的用户总分信息（0）

可进一步优化封装为 **双方游戏信息类 + 问题信息类**

#### (7). 分数选项的反馈信息 `ScoreSelectedInfo`

```
@Data
@AllArgsConstructor
@NoArgsConstructor
public class ScoreSelectedInfo {
    private UserMatchInfo userMatchInfo;
    private String userSelectedAnswer;
}
```

包含用户信息 UserMatchInfo 及 **userSelectedAnswer**

顾名思义 其为用户每一题所选择的答案 此程序中记录的是问题的答案 （数组中的具体值）

可优化改变换成记录数组对应索引etc

### 2、异常处理类

#### (1). 错误码定义的统一接口

```
public interface IServerError {
​
    /**
     * 返回错误码
     *
     * @return 错误码
     */
    Integer getErrorCode();
​
    /**
     * 返回错误详细信息
     *
     * @return 错误详细信息
     */
    String getErrorDesc();
}
```

#### (2). 运行时错误

```
public enum GameServerError implements IServerError {
​
    /**
     * 枚举型错误码
     */
    WEBSOCKET_ADD_USER_FAILED(4018, "用户进入匹配模式失败"),
    MESSAGE_TYPE_ERROR(4019, "websocket 消息类型错误"),
    ;
​
    private final Integer errorCode;
    private final String errorDesc;
​
    GameServerError(Integer errorCode, String errorDesc) {
        this.errorCode = errorCode;
        this.errorDesc = errorDesc;
    }
​
    @Override
    public Integer getErrorCode() {
        return errorCode;
    }
​
    @Override
    public String getErrorDesc() {
        return errorDesc;
    }
}
```

枚举错误类型及错误码

#### (3). 运行时异常

```
public class GameServerException extends RuntimeException {
​
    private Integer code;
​
    private String message;
​
    public GameServerException(GameServerError error) {
        super(error.getErrorDesc());
        this.code = error.getErrorCode();
    }
​
    public Integer getCode() {
        return code;
    }
​
    public void setCode(Integer code) {
        this.code = code;
    }
}
```

统一规范抛出的异常及其错误类型

### 3、游戏状态枚举类

```
public enum EnumRedisKey {
​
    /**
     * userOnline 在线状态
     */
    USER_STATUS,
    /**
     * userOnline 匹配信息
     */
    USER_MATCH_INFO,
    /**
     * 房间
     */
    ROOM;
​
    public String getKey() {
        return this.name();
    }
}
```

使用枚举类规定游戏中玩家的状态 并且使用redis进行存储

### 4、ws主类

此部分代码分为多板块

此类完整代码见附

#### (1). 注入的相关类

```
private Session session;
​
private String userId;
​
static MatchCacheUtil matchCacheUtil;
// 修改 查看用户的在线状态 客户端存储状态工具类
​
static Lock lock = new ReentrantLock();
static Condition matchCond = lock.newCondition();
// 锁 防止并发异常情况
​
static QuestionService questionService;
// 题目业务类 用于在题库中随机获取题目
​
static CompetitionService competitionService;
// 比赛业务类 用于获取用户段位信息等 pk相关的功能信息
​
static UserService userService;
// 用户业务类 用于获取用户个人信息
​
static AnswerSituationUtil answerSituationUtil;
// 存储用户单轮答案信息 工具类
​
​
@Autowired
public void setQuestionService(QuestionService questionService) {
    ChatWebsocket.questionService = questionService;
}
​
@Autowired
public void setQuestionService(CompetitionService competitionService) {
    ChatWebsocket.competitionService = competitionService;
}
​
@Autowired
public void setQuestionService(UserService userService) {
    ChatWebsocket.userService = userService;
}
​
@Autowired
public void setMatchCacheUtil(MatchCacheUtil matchCacheUtil) {
    ChatWebsocket.matchCacheUtil = matchCacheUtil;
}
​
@Autowired
public void setAnswerSituationUtil(AnswerSituationUtil answerSituationUtil) {
    ChatWebsocket.answerSituationUtil = answerSituationUtil;
}
​
// 类单例模式注入相关业务工具类
```

详细工具类见下一部分

#### (2). 主要架构

```
@OnOpen
public void onOpen(@PathParam("userId") String userId, Session session) {
    System.out.println(session);
    log.info("ChatWebsocket open 有新连接加入 userId: {}", userId);
    this.userId = userId;
    this.session = session;
    matchCacheUtil.addClient(userId, this);
​
    log.info("ChatWebsocket open 连接建立完成 userId: {}", userId);
}
```

**onOpen:** 建立ws连接时调用 使用工具类存储当前客户端的 **id和webSocket对象** 入redis中 便于后期调用

* * *

```
@OnError
public void onError(Session session, Throwable error) {
​
    log.error("ChatWebsocket onError 发生了错误 userId: {}, errorMessage: {}", userId, error.getMessage());
​
    matchCacheUtil.removeClinet(userId);
    matchCacheUtil.removeUserOnlineStatus(userId);
    matchCacheUtil.removeUserFromRoom(userId);
    matchCacheUtil.removeUserMatchInfo(userId);
​
    log.info("ChatWebsocket onError 连接断开完成 userId: {}", userId);
}
​
@OnClose
public void onClose() {
    log.info("ChatWebsocket onClose 连接断开 userId: {}", userId);
​
    matchCacheUtil.removeClinet(userId);
    matchCacheUtil.removeUserOnlineStatus(userId);
    matchCacheUtil.removeUserFromRoom(userId);
    matchCacheUtil.removeUserMatchInfo(userId);
​
    log.info("ChatWebsocket onClose 连接断开完成 userId: {}", userId);
}
```

**OnError:** 遇到异常时退出并调用 将用户信息经过工具类 从redis中移除

**OnClose:** 同理 断开连接时调用 正常使用时机为 **用户pk结束**

* * *

```
@OnMessage
public void onMessage(String message, Session session) {
​
    log.info("ChatWebsocket onMessage userId: {}, 来自客户端的消息 message: {}", userId, message);
​
    JSONObject jsonObject = JSON.parseObject(message);
    MessageTypeEnum type = jsonObject.getObject("type", MessageTypeEnum.class);
​
    log.info("ChatWebsocket onMessage userId: {}, 来自客户端的消息类型 type: {}", userId, type);
​
    if (type == MessageTypeEnum.MATCH_USER) {
        matchUser(jsonObject);
    } else if (type == MessageTypeEnum.PLAY_GAME) {
        toPlay(jsonObject);
    } else if (type == MessageTypeEnum.GAME_OVER) {
        gameover(jsonObject);
    } else {
        throw new GameServerException(GameServerError.WEBSOCKET_ADD_USER_FAILED);
    }
​
    log.info("ChatWebsocket onMessage userId: {} 消息接收结束", userId);
}
```

**OnMessage:** 收到客户端信息时调用 **ws实现功能关键部分！**

此处将整个游戏过程分割为三部分 分别为 **匹配玩家 游戏中 游戏结束**

#### (3). 实现逻辑方法

##### **1). 群发消息 `sendMessageAll`**

```
/**
 * 群发消息
 */
private void sendMessageAll(MessageReply<?> messageReply) {
​
    log.info("ChatWebsocket sendMessageAll 消息群发开始 userId: {}, messageReply: {}", userId, JSON.toJSONString(messageReply));
​
    Set<String> receivers = messageReply.getChatMessage().getReceivers();
    for (String receiver : receivers) {
        ChatWebsocket client = matchCacheUtil.getClient(receiver);
        client.session.getAsyncRemote().sendText(JSON.toJSONString(messageReply));
    }
​
    log.info("ChatWebsocket sendMessageAll 消息群发结束 userId: {}", userId);
}
```

此方法根据形参 确定信息的发出者 并从工具类中 **获取对方的webSocket对象** 异步发送到对方的客户端中

##### **2). 用户随机匹配对手 `matchUser`**

```
    /**
     * 用户随机匹配对手
     */
    @SneakyThrows
// 抛出异常注解
    private void matchUser(JSONObject jsonObject) {
​
        log.info("ChatWebsocket matchUser 用户随机匹配对手开始 message: {}, userId: {}", jsonObject.toJSONString(), userId);
​
        MessageReply<GameMatchInfo> messageReply = new MessageReply<>();
        ChatMessage<GameMatchInfo> result = new ChatMessage<>();
        result.setSender(userId);
        result.setType(MessageTypeEnum.MATCH_USER);
​
        lock.lock();
        try {
            // 设置用户状态为匹配中
//            TODO 修改工具类的类型 使他不只能存储id 也能存储玩家的段位
            matchCacheUtil.setUserInMatch(userId);
            matchCond.signal();
        } finally {
            lock.unlock();
        }
​
        // 创建一个异步线程任务，负责匹配其他同样处于匹配状态的其他用户
        Thread matchThread = new Thread(() -> {
            boolean flag = true;
            String receiver = null;
            while (flag) {
                // 获取除自己以外的其他待匹配用户
                lock.lock();
                try {
                    // 当前用户不处于待匹配状态 直接返回
                    if (matchCacheUtil.getUserOnlineStatus(userId).compareTo(StatusEnum.IN_GAME) == 0
//                            观察当前用户是否游戏中状态
                            || matchCacheUtil.getUserOnlineStatus(userId).compareTo(StatusEnum.GAME_OVER) == 0) {
//                        观察当前用户是否游戏结束 结算的状态
                        log.info("ChatWebsocket matchUser 当前用户 {} 已退出匹配", userId);
                        return;
                    }
                    // 当前用户取消匹配状态
                    if (matchCacheUtil.getUserOnlineStatus(userId).compareTo(StatusEnum.IDLE) == 0) {
                        // 当前用户取消匹配
                        messageReply.setCode(MessageCode.CANCEL_MATCH_ERROR.getCode());
                        messageReply.setDesc(MessageCode.CANCEL_MATCH_ERROR.getDesc());
//                        设定返回信息 将从匹配中的状态该为待匹配
                        Set<String> set = new HashSet<>();
                        set.add(userId);
                        result.setReceivers(set);
                        result.setType(MessageTypeEnum.CANCEL_MATCH);
                        messageReply.setChatMessage(result);
                        log.info("ChatWebsocket matchUser 当前用户 {} 已退出匹配", userId);
//                        发送返回信息
                        sendMessageAll(messageReply);
                        return;
                    }
​
//                    从room中获取对手的对象 这个receiver是对手的id
//                    可以在这里下手脚 加一个while循环 判断直至找到相同段位的用户为止
//                    TODO 直接在setUserMatchRoom那块 加入玩家的段位信息 需要改动工具类
                    String userDan = competitionService.showPlayersExtraDan(Integer.parseInt(userId));
                    while (true) {
                        receiver = matchCacheUtil.getUserInMatchRandom(userId);
//                        这里必须把判空放在上面 否则如果是队列中没有人在匹配 却给receiver调用了Integer.parseInt(receiver)方法 会报空指针
                        if (Objects.isNull(receiver))
                            break;
                        else if (userDan.equals(competitionService.showPlayersExtraDan(Integer.parseInt(receiver))))
                            break;
                    }
                    if (receiver != null) {
                        // 对手不处于待匹配状态
                        if (matchCacheUtil.getUserOnlineStatus(receiver).compareTo(StatusEnum.IN_MATCH) != 0) {
                            log.info("ChatWebsocket matchUser 当前用户 {}, 匹配对手 {} 已退出匹配状态", userId, receiver);
                        } else {
//                            进了这个else就表明用户已经匹配到状态正常的对手了
//                            设定对手的基本信息
                            matchCacheUtil.setUserInGame(userId);
                            matchCacheUtil.setUserInGame(receiver);
//                            将对手放入房间中 （指定唯一user）
                            matchCacheUtil.setUserInRoom(userId, receiver);
                            flag = false;
//                            匹配到了 令flag为false 跳出while循环
//                            此次匹配结束 进入开打状态
                        }
                    } else {
                        // 如果当前没有待匹配用户，进入等待队列
                        try {
                            log.info("ChatWebsocket matchUser 当前用户 {} 无对手可匹配", userId);
                            matchCond.await();
                        } catch (InterruptedException e) {
                            log.error("ChatWebsocket matchUser 匹配线程 {} 发生异常: {}",
                                    Thread.currentThread().getName(), e.getMessage());
                        }
                    }
                } finally {
                    lock.unlock();
                }
            }
​
            log.info("已找到玩家 双方分别为" + userId + "和" + receiver);
​
            UserMatchInfo senderInfo = new UserMatchInfo();
            UserMatchInfo receiverInfo = new UserMatchInfo();
            senderInfo.setUserId(userId);
            senderInfo.setScore(0);
            receiverInfo.setUserId(receiver);
            receiverInfo.setScore(0);
//            两个对象分别记录两个玩家的得分
​
            matchCacheUtil.setUserMatchInfo(userId, JSON.toJSONString(senderInfo));
            matchCacheUtil.setUserMatchInfo(receiver, JSON.toJSONString(receiverInfo));
//            初始化接下来pk中玩家的信息 (每一道题提交答案完成都会 刷新一次对应的得分)
​
            GameMatchInfo gameMatchInfo = new GameMatchInfo();
​
//            获取玩家段位 根据玩家段位来获取题目
            String dan = competitionService.showPlayersDan(Integer.parseInt(userId));
            List<Question> questions = questionService.getCompetitionQuestionsByDan(dan);
​
            gameMatchInfo.setQuestions(questions);
            gameMatchInfo.setSelfInfo(senderInfo);
            gameMatchInfo.setOpponentInfo(receiverInfo);
//            一次性获取所有题目
//            存入此次对战中的当前玩家 对方 题目
//            一个GameMatchInfo就代表一个玩家的对象
​
//            新增 存入此次pk中对方的用户名 头像
            UserWithValue userWithValue = userService.showUser(Integer.parseInt(userId));
            String username = userWithValue.getUser().getUsername();
            String userPic = userWithValue.getUserValue().getPic();
            gameMatchInfo.setSelfUsername(username);
            gameMatchInfo.setSelfPicAvatar(userPic);
​
            UserWithValue receiverValue = userService.showUser(Integer.parseInt(receiver));
            String receiverUsername = receiverValue.getUser().getUsername();
            String opponentPic = receiverValue.getUserValue().getPic();
            gameMatchInfo.setOpponentUsername(receiverUsername);
            gameMatchInfo.setOpponentPicAvatar(opponentPic);
​
            messageReply.setCode(MessageCode.SUCCESS.getCode());
            messageReply.setDesc(MessageCode.SUCCESS.getDesc());
//            确认返回信息的类型以及数据
​
            result.setData(gameMatchInfo);
            Set<String> set = new HashSet<>();
            set.add(userId);
            result.setReceivers(set);
            result.setType(MessageTypeEnum.MATCH_USER);
            messageReply.setChatMessage(result);
            sendMessageAll(messageReply);
​
//            自己的传给自己的 对面的传给对面的
            gameMatchInfo.setSelfInfo(senderInfo);
            gameMatchInfo.setOpponentInfo(receiverInfo);
​
            result.setData(gameMatchInfo);
            set.clear();
            set.add(receiver);
            result.setReceivers(set);
            messageReply.setChatMessage(result);
​
            sendMessageAll(messageReply);
​
            log.info("ChatWebsocket matchUser 用户随机匹配对手结束 messageReply: {}", JSON.toJSONString(messageReply));
​
        }, MATCH_TASK_NAME_PREFIX + userId);
        matchThread.start();
    }
```

基本思路为 改变玩家状态为匹配中 并且匹配相同状态 相同段位的对手 **(段位可按需增删)**

匹配的过程是异步多线程匹配 若没有相同状态的对手 则线程沉睡 直至有对手匹配为止 **(此处可以设置匹配超时时间进行优化)**

确认对手状态无误后 根据id获取双方信息 此轮pk中题目

最后通过 **sendMessageAll** 的方法将信息发送给自己与对方

执行步骤见代码注释

##### **3). 游戏中 `toPlay`**

```
    /**
     * 游戏中
     */
    @SneakyThrows
    public void toPlay(JSONObject jsonObject) {
//        每一道题提交了都会重新执行一次这个方法
//        (由答题方 执行)
        log.info("ChatWebsocket toPlay 用户更新对局信息开始 userId: {}, message: {}", userId, jsonObject.toJSONString());
​
        MessageReply<ScoreSelectedInfo> messageReply = new MessageReply<>();
//        返回的信息类型
​
//        下面的这个思路就是 从房间中找到对方 并且发送自己的分数更新信息给他
        ChatMessage<ScoreSelectedInfo> result = new ChatMessage<>();
        result.setSender(userId);
        String receiver = matchCacheUtil.getUserFromRoom(userId);
//        从房间中找出对面的对手是谁 发信息给他
        Set<String> set = new HashSet<>();
        set.add(receiver);
        result.setReceivers(set);
        result.setType(MessageTypeEnum.PLAY_GAME);
//        设置消息的发送方 和 接收方 以及消息类型 (游戏中)
​
//        获取新的得分 并且重新赋值给当前的user   (当前的user就是得分的那个)
        UserMatchChoice userMatchChoice = jsonObject.getObject("data", UserMatchChoice.class);
        Integer newScore = userMatchChoice.getUserScore();
        String userSelectedAnswer = userMatchChoice.getUserSelectedAnswer();
​
//        获取answerSituation对象 此对象中是所有正在游戏中的用户的回答信息 暂时存在这里
        answerSituationUtil.addAnswer(userId, userSelectedAnswer);
​
        UserMatchInfo userMatchInfo = new UserMatchInfo();
        userMatchInfo.setUserId(userId);
        userMatchInfo.setScore(newScore);
​
//        setUserMatchInfo所改变的数据是 同一时刻所有对战的用户的信息
//        在这里set是根据当前用户的id
//        重新设置一下对应的用户对战信息
        matchCacheUtil.setUserMatchInfo(userId, JSON.toJSONString(userMatchInfo));
​
//        设置响应数据的类型
//        更新 同时发送对面所选的选项
        result.setData(new ScoreSelectedInfo(userMatchInfo, userSelectedAnswer));
        messageReply.setCode(MessageCode.SUCCESS.getCode());
        messageReply.setDesc(MessageCode.SUCCESS.getDesc());
        messageReply.setChatMessage(result);
​
//        返回包含当前用户的新信息的响应数据
        sendMessageAll(messageReply);
​
        log.info("ChatWebsocket toPlay 用户更新对局信息结束 userId: {}, userMatchInfo: {}", userId, JSON.toJSONString(userMatchInfo));
    }
```

pk中 每一道题答完后 客户端往服务器发起的请求类型

主要思路是 根据信息的发出方 从redis中的房间机制获取他的对手 **(在匹配的时候会将一轮对战中双方的id存入redis 可理解成放入房间 防止第三者客户端进入 对pk过程进行干扰)** 之后将答题情况发送给对方

##### **4). 游戏结束 `gameover`**

```
    /**
     * 游戏结束
     */
    public void gameover(JSONObject jsonObject) {
​
        log.info("ChatWebsocket gameover 用户对局结束 userId: {}, message: {}", userId, jsonObject.toJSONString());
​
//        设置响应数据类型
        MessageReply<RoomAnswerSituation> messageReply = new MessageReply<>();
​
//        设置响应数据 改变玩家的状态
        ChatMessage<RoomAnswerSituation> result = new ChatMessage<>();
        result.setSender(userId);
        String receiver = matchCacheUtil.getUserFromRoom(userId);
        result.setType(MessageTypeEnum.GAME_OVER);
        lock.lock();
        try {
//            设定用户为游戏结束的状态
            matchCacheUtil.setUserGameover(userId);
            if (matchCacheUtil.getUserOnlineStatus(receiver).compareTo(StatusEnum.GAME_OVER) == 0) {
                messageReply.setCode(MessageCode.SUCCESS.getCode());
                messageReply.setDesc(MessageCode.SUCCESS.getDesc());
​
                //        记录赢了的玩家的ID
                Integer winnerId = jsonObject.getInteger("data");
                boolean isUpdate = competitionService.updateUserStar(winnerId);
                if (!isUpdate) {
                    messageReply.setCode(MessageCode.SYSTEM_ERROR.getCode());
                    messageReply.setDesc(MessageCode.SYSTEM_ERROR.getDesc());
                }
​
//                获取对战后的对战信息
                AnswerSituation selfAnswer = answerSituationUtil.getAnswer(userId);
                AnswerSituation opponentAnswer = answerSituationUtil.getAnswer(receiver);
                RoomAnswerSituation roomAnswerSituation = new RoomAnswerSituation(userId, receiver, selfAnswer, opponentAnswer);
                result.setData(roomAnswerSituation);
​
//                设置完结后的返回信息
                messageReply.setChatMessage(result);
                Set<String> set = new HashSet<>();
                set.add(receiver);
                result.setReceivers(set);
                sendMessageAll(messageReply);
//                屎山会出手 两边全部发
                set.clear();
                set.add(userId);
                result.setReceivers(set);
                sendMessageAll(messageReply);
​
//                移除属于游戏中的游戏信息
                matchCacheUtil.removeUserMatchInfo(userId);
                matchCacheUtil.removeUserFromRoom(userId);
​
//                移除属于这一次的游戏选择信息
                answerSituationUtil.removeAnswer(userId);
                answerSituationUtil.removeAnswer(receiver);
            }
        } finally {
            lock.unlock();
        }
​
        log.info("ChatWebsocket gameover 对局 [{} - {}] 结束", userId, receiver);
    }
```

代码中通过前端判断题目数组遍历完成 判断双方分数 发送gameover状态信息

前端通过比较双方总分 将胜利用户的id发回给后端 即此状态信息中的 **T data**

后端将其状态转换 并且将对应的双方**此轮对战信息 包括总分 获胜者 对方的回答情况** 发回给双方客户端

至此 一轮pk结束

### 5、配置类及工具类

#### (1). WebSocket配置类

```
@Configuration
@EnableWebSocket
public class WebsocketConfig {
    @Bean
    public ServerEndpointExporter serverEndpointExporter(){
        return new ServerEndpointExporter();
    }
}
```

#### **(2). AnswerSituation 用户答题情况存储工具类**

```
@Component
//用户答题情况 工具类
public class AnswerSituationUtil {
​
    private static final Map<String, AnswerSituation> ANSWER_SITUATION = new HashMap<>();
​
//    新增答案
    public void addAnswer(String userId,String answer){
        boolean isScored = ANSWER_SITUATION.containsKey(userId);
        if (isScored)
            ANSWER_SITUATION.get(userId).getSelfAnswerSituations().add(answer);
        if (!isScored) {
            ArrayList<String> answers = new ArrayList<>();
            answers.add(answer);
            ANSWER_SITUATION.put(userId,new AnswerSituation(answers));
        }
    }
​
//    获取用户所有答案
    public AnswerSituation getAnswer(String userId){
        boolean isContain = ANSWER_SITUATION.containsKey(userId);
        if (!isContain)
            return null;
        return ANSWER_SITUATION.get(userId);
    }
​
//    移除答案
    public boolean removeAnswer(String userId){
        boolean isContain = ANSWER_SITUATION.containsKey(userId);
        if (!isContain)
            return false;
        ANSWER_SITUATION.remove(userId);
        return true;
    }
}
```

主要存储 记录 清除 用户每一轮答题的缓存

可优化存进 **redis** 中

#### (3). **MatchCacheUtil 存储用户在线状态及其客户端工具类**

```
@Component
public class MatchCacheUtil {
​
    /**
     * 用户 userId 为 key，ChatWebsocket 为 value
     */
    private static final Map<String, ChatWebsocket> CLIENTS = new HashMap<>();
​
    /**
     * key 是标识存储用户在线状态的 EnumRedisKey，value 为 map 类型，其中用户 userId 为 key，用户在线状态 为 value
     */
    @Resource
    private RedisTemplate<String, Map<String, String>> redisTemplate;
​
    /**
     * 添加客户端
     */
    public void addClient(String userId, ChatWebsocket websocket) {
        CLIENTS.put(userId, websocket);
    }
​
    /**
     * 移除客户端
     */
    public void removeClinet(String userId) {
        CLIENTS.remove(userId);
    }
​
    /**
     * 获取客户端
     */
    public ChatWebsocket getClient(String userId) {
        return CLIENTS.get(userId);
    }
​
    /**
     * 移除用户在线状态
     */
    public void removeUserOnlineStatus(String userId) {
        redisTemplate.opsForHash().delete(EnumRedisKey.USER_STATUS.getKey(), userId);
    }
​
    /**
     * 获取用户在线状态
     */
    public StatusEnum getUserOnlineStatus(String userId) {
        Object status = redisTemplate.opsForHash().get(EnumRedisKey.USER_STATUS.getKey(), userId);
        if (status == null) {
            return null;
        }
        return StatusEnum.getStatusEnum(status.toString());
    }
​
    /**
     * 设置用户为 IDLE 状态
     */
    public void setUserIDLE(String userId) {
        removeUserOnlineStatus(userId);
        redisTemplate.opsForHash().put(EnumRedisKey.USER_STATUS.getKey(), userId, StatusEnum.IDLE.getValue());
    }
​
    /**
     * 设置用户为 IN_MATCH 状态
     */
    public void setUserInMatch(String userId) {
        removeUserOnlineStatus(userId);
        redisTemplate.opsForHash().put(EnumRedisKey.USER_STATUS.getKey(), userId, StatusEnum.IN_MATCH.getValue());
    }
​
    /**
     * 随机获取处于匹配状态的用户（除了指定用户外）
     */
    public String getUserInMatchRandom(String userId) {
        Optional<Map.Entry<Object, Object>> any = redisTemplate.opsForHash().entries(EnumRedisKey.USER_STATUS.getKey())
                .entrySet().stream().filter(entry -> entry.getValue().equals(StatusEnum.IN_MATCH.getValue()) && !entry.getKey().equals(userId))
                .findAny();
        return any.map(entry -> entry.getKey().toString()).orElse(null);
    }
​
    /**
     * 设置用户为 IN_GAME 状态
     */
    public void setUserInGame(String userId) {
        removeUserOnlineStatus(userId);
        redisTemplate.opsForHash().put(EnumRedisKey.USER_STATUS.getKey(), userId, StatusEnum.IN_GAME.getValue());
    }
​
    /**
     * 设置处于游戏中的用户在同一房间
     */
    public void setUserInRoom(String userId1, String userId2) {
        redisTemplate.opsForHash().put(EnumRedisKey.ROOM.getKey(), userId1, userId2);
        redisTemplate.opsForHash().put(EnumRedisKey.ROOM.getKey(), userId2, userId1);
    }
​
    /**
     * 从房间中移除用户
     */
    public void removeUserFromRoom(String userId) {
        redisTemplate.opsForHash().delete(EnumRedisKey.ROOM.getKey(), userId);
    }
​
    /**
     * 从房间中获取用户
     */
    public String getUserFromRoom(String userId) {
        return redisTemplate.opsForHash().get(EnumRedisKey.ROOM.getKey(), userId).toString();
    }
​
    /**
     * 设置处于游戏中的用户的对战信息
     */
    public void setUserMatchInfo(String userId, String userMatchInfo) {
        redisTemplate.opsForHash().put(EnumRedisKey.USER_MATCH_INFO.getKey(), userId, userMatchInfo);
    }
​
    /**
     * 移除处于游戏中的用户的对战信息
     */
    public void removeUserMatchInfo(String userId) {
        redisTemplate.opsForHash().delete(EnumRedisKey.USER_MATCH_INFO.getKey(), userId);
    }
​
    /**
     * 设置处于游戏中的用户的对战信息
     */
    public String getUserMatchInfo(String userId) {
        return redisTemplate.opsForHash().get(EnumRedisKey.USER_MATCH_INFO.getKey(), userId).toString();
    }
​
    /**
     * 设置用户为游戏结束状态
     */
    public synchronized void setUserGameover(String userId) {
        removeUserOnlineStatus(userId);
        redisTemplate.opsForHash().put(EnumRedisKey.USER_STATUS.getKey(), userId, StatusEnum.GAME_OVER.getValue());
    }
}
```

设置并改变用户的在线状态 **利用redis + 枚举类**

在每一轮游戏结束之后 将其移除缓存

#### (4). **MessageCode 响应码**

```
@Getter
public enum MessageCode {
​
    /**
     * 响应码
     */
    SUCCESS(2000, "连接成功"),
    USER_IS_ONLINE(2001, "用户已存在"),
    CURRENT_USER_IS_INGAME(2002, "当前用户已在游戏中"),
    MESSAGE_ERROR(2003, "消息错误"),
    CANCEL_MATCH_ERROR(2004, "用户取消了匹配"),
    SYSTEM_ERROR(2005,"系统错误");
​
    private final Integer code;
    private final String desc;
​
    MessageCode(Integer code, String desc) {
        this.code = code;
        this.desc = desc;
    }
}
```

枚举类定义封装ws使用中会出现的错误

#### **(5). MessageTypeEnum 用户状态枚举类**

```
public enum MessageTypeEnum {
    /**
     * 匹配对手
     */
    MATCH_USER,
    /**
     * 游戏开始
     */
    PLAY_GAME,
    /**
     * 游戏结束
     */
    GAME_OVER,
}
```

枚举类统一定义ws连接中**OnMessage**中会出现的消息类型

前后端根据判断消息类型 判断执行的逻辑 和方法执行的阶段

#### (6). StatusEnum 用户状态枚举类

```
public enum StatusEnum {
​
    /**
     * 待匹配
     */
    IDLE,
    /**
     * 匹配中
     */
    IN_MATCH,
    /**
     * 游戏中
     */
    IN_GAME,
    /**
     * 游戏结束
     */
    GAME_OVER,
    ;
​
    public static StatusEnum getStatusEnum(String status) {
        switch (status) {
            case "IDLE":
                return IDLE;
            case "IN_MATCH":
                return IN_MATCH;
            case "IN_GAME":
                return IN_GAME;
            case "GAME_OVER":
                return GAME_OVER;
            default:
                throw new GameServerException(GameServerError.MESSAGE_TYPE_ERROR);
        }
    }
​
    public String getValue() {
        return this.name();
    }
}
```

确认用户此时的状态 为 **匹配中 待匹配 游戏中 游戏结束**

-   注：**用户的状态 ≠ 消息类型**

