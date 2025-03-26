---
title: 使用Java & WebSocket & JS实现简单实时双人协同pk答题——前端
date: 2024-03-10 16:30:52
tags: Java
---
## 引入
在实时双人PK答题应用中，前端主要负责与WebSocket服务器的交云通信，实现实时互动功能。通过JavaScript建立WebSocket连接后，前端将发送和接收消息以实现玩家匹配、题目显示、答题、分数更新和游戏结束等功能。在用户界面上，通过监听点击事件来触发匹配对手、提交答案和结束游戏的操作，同时动态更新UI以反映游戏状态的变化。例如，当用户匹配成功后，前端将渲染题目和答案选项，并在每次提交答案后更新双方的分数。在游戏结束时，前端会显示最终的胜负结果，并可选择重新匹配开始新的对战。整个过程中，前端需要处理来自WebSocket的消息，根据不同类型的消息（如匹配用户、游戏进行中和游戏结束）执行相应的UI更新和逻辑处理。

此文对应前文《使用Java + WebSocket实现简单实时双人协同pk答题》中的后端逻辑


## 二、WebSocket 前端

此处只介绍大致思路与相关js函数

### 0、记录用户id标识

```
let token = `${sessionStorage.getItem('sign1')}`
​
axios({
        method: 'GET',
        url: 'http://你说的对:3000/users',
        headers: {
            'token': `${token}`
        }
    })
    .then(res => { // 接口数据
        console.log(res.data);
        let { data } = res.data
        let { user } = data
        // 存储userId到 sessionStorage
        sessionStorage.setItem('userId', user.userId);
    })
​
.catch(error => { //  处理错误
    console.error(error);
});
```

将数据存储到**sessionStorage**中

### 1、大概流程

```
// 点击汇总页面的pk,开始链接到websocket
const inner3 = document.querySelector('.panel:nth-of-type(3) .inner')
console.log(inner3)
inner3.addEventListener('click', function() {
        let userId = sessionStorage.getItem('userId')
        console.log(userId)
        connect(userId)
    })
    // 点击开始匹配,进行匹配,并且进入到答题界面
const switchs = document.querySelector('.pk input')
switchs.addEventListener('click', function() {
    // 开始随机匹配
    let userId = sessionStorage.getItem('userId')
    console.log(userId)
    matchUser(userId)
    const fight = document.querySelector('.fight')
    const pk = document.querySelector('.pk')
    let timer = setTimeout(function() {
            pk.style.display = 'none'
            fight.style.display = 'block'
        }, 1000)
        // 渲染自己的信息
    userInfo()
    const questionBox = document.querySelector('.questions>div')
    questionBox.innerHTML = '正在寻找对手...'
})
```

其中调用的**connect**函数是重点 相关逻辑主要靠其实现

**matchUser**是匹配对手的函数

```
function connect(userId){
var socketurl "ws://yourServerUrl:3000/competition/" + userId;
socket = new Websocket(socketurl);
//在此触发OnOpen
//打开事件
socket.onopen = function(){...};
//在此触发OnMessage
//获得消息事件
socket.onmessage = function(msg){...};
//在此触发onclose
//关闭事件
socket.onclose = function(){...};
//在此触发OnError
//发生了错误事件
socket.onerror = function(){...};
```

**connect**函数的大概架构如上

**onMessage**为主要逻辑实现 下一部分分析

**matchUser**内容见下一部分

### 2、OnOpen打开连接及OnError错误处理

```
socket.onopen = function() {
    console.log("websocket 已打开 userId: " + userId);
};
socket.onerror = function() {
    console.log("websocket 发生了错误 userId : " + userId);
}
```

此处不多赘述错误处理和连接，可在对应函数处记录日志或心跳响应等

### 3、OnMessage响应信息及对应请求函数

```
    // 在此触发OnMessage
    //获得消息事件
    socket.onmessage = function(msg) {
        // 此处编写得到消息之后的具体逻辑
        // 提交每一题之后 需要更新玩家的分数和
        // chatMessage就是真正的类 响应数据
        let chatMessage = msg.data;
        chatMessage = JSON.parse(chatMessage);
        let message = chatMessage.chatMessage
        let data = message.data;
        let type = message.type;
            // 以上均为通用代码
            // 正确答案的数组
        let rightAnswer = []
        var serverMsg = "收到服务端信息: " + msg.data;
        console.log(serverMsg);
    };
```

**onMessage** 表示收到服务器消息之后的逻辑 上方步骤将数据转换并赋值给相关变量

#### (1). MATCH_USER

前端发送开始匹配信号

```
// 随机匹配
function matchUser(userId) {
    var chatMessage = {};
    var sender = userId;
    var type = "MATCH_USER";
    chatMessage.sender = sender;
    chatMessage.type = type;
    console.log("用户:" + sender + "开始匹配......");
    socket.send(JSON.stringify(chatMessage));
}
```

无需发送数据

```
            // 如果接收到的是匹配时 代表此时已经有用户匹配成功 后端发送题目以及 对应的用户信息
        if (type === "MATCH_USER") {
            let gameMatchInfo = message.data;
            console.log(gameMatchInfo)
                // gameMatchInfo对应chatMessage中的T data
            let questionList = gameMatchInfo.questions;
            console.log(questionList)
                // 获取到所有问题的题目及答案
                // questionList表示此次对战中的题库
​
            // 记录正确答案
            for (let i = 0; i < questionList.length; i++) {
                rightAnswer.push(questionList[i].rightAnswer)
            }
            console.log(rightAnswer)
            let userId = sessionStorage.getItem('userId')
                // 异步函数
            async function wait(questionList, rightAnswer, userId) {
                // 渲染题目到页面上
                await questionDisplay(questionList)
                choose(rightAnswer, userId)
                displayOver(questionList, rightAnswer)
            }
            // 调用异步函数
            wait(questionList, rightAnswer, userId)
                // 同时需要获取到对面的用户的信息
            let selfInfo = gameMatchInfo.selfInfo;
​
            // selfInfo是自己的信息
            // selfInfo则代表的是GameMatchInfo中selfInfo的属性
            let selfId = selfInfo.userId;
            if (selfId === userId) {
                selfUsername = gameMatchInfo.selfUsername;
                selfPicAvatar = gameMatchInfo.selfPicAvatar;
                let opponentInfo = gameMatchInfo.opponentInfo;
                // opponentInfo则是对面的信息
                // 获取到对面用户的id 头像 名字
                opponentUserId = opponentInfo.userId;
                opponentUsername = gameMatchInfo.opponentUsername;
                opponentPicAvatar = gameMatchInfo.opponentPicAvatar
                sessionStorage.setItem('opponentId', opponentUserId)
​
                // 渲染对手的信息
                opponentinfo(opponentPicAvatar, opponentUsername)
            } else {
                opponentUserId = selfId
                opponentUsername = gameMatchInfo.selfUsername;
                opponentPicAvatar = gameMatchInfo.selfPicAvatar;
                sessionStorage.setItem('opponentId', opponentUserId)
​
                    // 渲染对手的信息
                opponentinfo(opponentPicAvatar, opponentUsername)
            }
​
        }
```

这个阶段代表的是 匹配到用户了 未开始对局 初始化数据 **(双方头像账户名id + 题目信息)**

对应后端发送信息中的 **GameMatchInfo**

#### (2). PLAY_GAME

按照pk中的游戏进程 每一次交互产生在玩家确认题目答案并提交之后 服务器将新的分数变化告知客户端

即 提交答案

```
function commitAnswer(score, userSelectedAnswerIndex, userId) {
    let chatMessage = {};
    let sender = userId;
    let type = "PLAY_GAME";
​
    // 如果答对了就更新分数 客户端向服务器发起请求
    // 如果没答对 也发送请求 此时也会执行代码 但是分数不会有变化
    // userScore是玩家的积分
    // 发送玩家的新得分以及自己的选项
    var data = {
        userScore: score,
        userSelectedAnswer: userSelectedAnswerIndex
    }
    chatMessage.sender = sender;
    chatMessage.data = data;
    chatMessage.type = type;
    console.log("用户:" + sender + "更新分数为" + data);
    console.log(chatMessage)
    socket.send(JSON.stringify(chatMessage));
    // 这里标记当前用户已经选择了
    isUserSelect = true;
}
```

此处需要发送**用户的总分**以及**用户的选择的答案**

```
        if (type === "PLAY_GAME") {
            let selfId = message.data.userMatchInfo.userId
            if (selfId === userId) {
                // 更新对方的分数
                const opponentScore = document.querySelector('.opponent-num')
                opponentnum = parseInt(opponentScore.innerHTML)
                let score = message.data.userMatchInfo.score
                opponentScore.innerHTML = score
                
            } else {
                option2 = true
                let opponentId = selfId
                const opponentScore = document.querySelector('.opponent-num')
                opponentnum = parseInt(opponentScore.innerHTML)
                let score = message.data.userMatchInfo.score
                opponentScore.innerHTML = score  
                
                if (option2 && option1) {
                    const questions = document.querySelector('.questions>div');
                    r++
                    questions.style.top = -520 * r + 'px'
                    
                    option1 = false
                    option2 = false
                    // 重置双方选或否
                }
            }
​
            // 这个data目前表示的是scoreSelectedInfo的匿名对象
            opponentSelectedAnswerIndex = data.userSelectedAnswerIndex;
            // 更新对面用户的分数
            opponentScore = data.userMatchInfo.score;
            isOpponentSelect = true;
            // 更新完分数了 这时候需要重新渲染出下一题 依次进行循环
        }
```

这个阶段代表的是 开始对局了之后所接受到的对方的信息

先进行对信息发送者 **sender** 的一个判断

本程序设计是在答题过程中 用户每回答一题 都将用户的回答情况广播给比赛的双方 所以在接收到状态为**对战中**的信息时

首先要判断信息的发出方是谁 **(客户端执行)** 换而言之 客户端需要判断自己**是否此信息的发出方**

如果不是 则说明对方答题情况有变化 渲染

如果是 则说明己方答题情况变化 渲染 (更建议将渲染己方的过程放置在己方答题之后即时进行)

#### (3). GAME_OVER

当题目遍历完了之后 由游戏中状态**PLAY_GAME**切换为**GAME_OVER**

```
// 按照游戏流程 写完所有的题之后 需要到结算页面
// 游戏结束
// 结束的时候 要告诉服务器谁是获胜者 把获胜者的id传过去吧
function gameover(userId) {
    let chatMessage = {};
    let data = null;
​
    data = userId;
    var sender = userId;
    var type = "GAME_OVER";
    chatMessage.sender = sender;
    chatMessage.type = type;
    chatMessage.data = data;
    console.log("用户:" + sender + "结束游戏");
    socket.send(JSON.stringify(chatMessage));
    userScore = 0;
    opponentScore = 0;
}
```

可知这里的data是 获胜者的id

服务器将胜者告诉客户端 后台对其决定积分增减etc

```
        if (type === "GAME_OVER") {
            if (userId === data.receiver) {
                // 渲染结算页面的我的答案
                const userlist = document.querySelectorAll('.user-list li')
                    // 渲染对手的答案
                const opponentlist = document.querySelectorAll('.opponent-list li')
                for (let i = 0; i < userlist.length; i++) {
                    if (data.opponentAnswerSituations.selfAnswerSituations[i] !== rightAnswer[i]) {
                        userlist[i].backgroundColor = 'red'
                    } else {
                        userlist[i].backgroundColor = 'green'
                    }
                    if (data.selfAnswerSituations.selfAnswerSituations[i] !== rightAnswer[i]) {
                        opponentlist[i].backgroundColor = 'red'
                    } else {
                        opponentlist[i].backgroundColor = 'green'
                    }
                    userlist[i].innerHTML = data.opponentAnswerSituations.selfAnswerSituations[i]
                    opponentlist[i].innerHTML = data.selfAnswerSituations.selfAnswerSituations[i]
                }
            } else {
                // 渲染结算页面的我的答案
                const userlist = document.querySelectorAll('.user-list li')
                    // 渲染对手的答案
                const opponentlist = document.querySelectorAll('.opponent-list li')
                for (let i = 0; i < userlist.length; i++) {
                    opponentlist[i].innerHTML = data.opponentAnswerSituations.selfAnswerSituations[i]
                    userlist[i].innerHTML = data.selfAnswerSituations.selfAnswerSituations[i]
                }
            }
​
        }
​
```

本程序规定触发**gameover**状态是单个用户所决定的 当满足触发gameover的对应条件时 前端将gameover携带获胜者id返回后端**用户A**

后端以上方所返回**用户A**为**sender**的返回双方答题情况

前端通过判断当前用户id是否sender 来确认用户的身份 并将自己以及对方的答题情况保存并渲染

### 4、OnClose断开连接

```
const turnon = document.querySelector('.turn-on')
turnon.addEventListener('click', function() {
    let userId = sessionStorage.getItem('userId')
        //关闭事件
    socket.close()
    socket.onclose = function() {
        console.log("websocket 已关闭 userId: " + userId);
    };
```

使用点击则关闭大法 至此断开websocket连接 一轮pk结束

### **issue**

可实现**再来一局**功能 大致思路为

在响应完gameover函数后 重新**matchUser**或直接**toPlay**

前者直接跳转为匹配中的状态 相当于退出重进

后者跳转为游戏中状态 需要刷新重新发送题库

可优化当匹配队列中无其他用户时空等待的情况

将用户回答情况工具类结合redis进行优化