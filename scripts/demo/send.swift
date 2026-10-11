// 向调试版 App 发送调试命令（DistributedNotification "dict.debug"），用法: send <命令>
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("dict.debug"), object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true)
