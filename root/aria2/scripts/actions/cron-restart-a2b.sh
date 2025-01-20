#!/bin/bash

# 获取环境变量 CRA2B 的值
CRA2B_VALUE=$CRA2B

# 检查 CRA2B 的值是否为 "false"
if [ "$CRA2B_VALUE" = "false" ]; then
    # 删除现有的 aria2b cron 任务
    (crontab -l | grep -v "ps -ef | grep aria2b | grep -v grep | awk '{print \$2}' | xargs kill -9") | crontab -
    echo "CRA2B 设置为 false。已移除定时重启 aria2b 定时任务。"
else
    # 使用 sed 提取用户输入中的数字部分
    HOURS=$(echo "$CRA2B_VALUE" | sed 's/[^0-9]*//g')
    
    # 检查 CRA2B 的值是否在 "1-24h" 范围内
    if [[ $HOURS =~ ^[1-9]$|^1[0-9]$|^2[0-4]$ ]]; then
        # 删除现有的 aria2b cron 任务
        (crontab -l | grep -v "ps -ef | grep aria2b | grep -v grep | awk '{print \$2}' | xargs kill -9") | crontab -
        echo "已移除现有的定时重启 aria2b 任务。"

        # 设置新的 cron job，在每小时的整点执行重启 aria2b 进程的命令
        (crontab -l ; echo "0 */$HOURS * * * ps -ef | grep aria2b | grep -v grep | awk '{print \$2}' | xargs kill -9") | crontab -
        echo "已设置定时任务，在每 $HOURS 小时的整点执行重启 aria2b 进程的命令。"
    else
        # 默认将 CRA2B 设置为 2 小时
        HOURS=2
        # 删除现有的 aria2b cron 任务
        (crontab -l | grep -v "ps -ef | grep aria2b | grep -v grep | awk '{print \$2}' | xargs kill -9") | crontab -
        echo "CRA2B 的值无效。已将 CRA2B 设置为默认值 2 小时。"

        # 设置新的 cron job，在整点执行重启 aria2b 进程的命令
        (crontab -l ; echo "0 */$HOURS * * * ps -ef | grep aria2b | grep -v grep | awk '{print \$2}' | xargs kill -9") | crontab -
        echo "已设置定时任务，在每 $HOURS 小时的整点执行重启 aria2b 进程的命令。"
    fi
fi