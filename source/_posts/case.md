---
title: case
date: 2025-03-13 20:20:34
tags:
cover: https://img.alicdn.com/imgextra/i1/2200540853987/O1CN01KTQhl51fK69k6k1kD_!!2200540853987.jpg
---

通过指定query 为其构造生成选择题的评测集prompt 让他生成对应的选择题选项 并且标注上选项的错误原因以及正确答案

通过prompt将大模型输出的内容再度美化成为json格式

将这个json格式的数据做一定的清晰后进行乱序 提取其中问题选项

与原query结合 构造出一道完整的选择题

调用大模型尝试写这道题 同理流程 得到最终答案
