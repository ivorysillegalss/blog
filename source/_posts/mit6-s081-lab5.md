---
title: mit6.s081 lab5
date: 2025-02-10 00:45:40
tags: mit6.s081
---

不知道官网上为什么找不到lazylab 仓库中也没有lazy的分支 暂时跳过了

## Copy On Write

work:

- 复制进程的时候 共享页面而非复制 将所有页面设置为只读（标记COW情景） 修改uvmcopy函数

- 识别页面错误时 分配新页面 新页面可以设置PTE_W位

-  设计引用计数法 添加时机：fork 删除时机：删除引用的时候

- RSW中记录当时是否为COW场景 RSW记录引用次数 √



页表相关数据

在xv6中 页表并没有其他信息 是通过一个指针来进行保存的

页表条目（PTE）位按照以下结构来组织：

| 位范围 | 含义                               |
| ------ | ---------------------------------- |
| 0      | `PTE_V` (Valid)                    |
| 1      | `PTE_R` (Read)                     |
| 2      | `PTE_W` (Write)                    |
| 3      | `PTE_X` (Execute)                  |
| 4      | `PTE_U` (User)                     |
| 5      | `PTE_G` (Global)                   |
| 6      | `PTE_A` (Accessed)                 |
| 7      | `PTE_D` (Dirty)                    |
| 8-10   | 保留（可能有用于架构扩展的位）     |
| 11-62  | 页表的物理地址（具体按页大小分配） |
| 63     | 保留位，可能是用于扩展的位         |
