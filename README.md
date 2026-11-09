# Keystone Android FFI 插件

单独目录保存 Keystone 源码、构建脚本和小鱼 Lua FFI 调用入口，不改小鱼源码。

- Keystone：0.9.2，Git 提交 `dc7932e`。
- Android 插件 ABI：`arm64-v8a`、`x86_64`。
- 汇编目标：AArch64、x86-64；不编入其他后端。
- 发布产物位于 `package/keystone/<ABI>/libkeystone.so`，已剥离非必要符号。
- `keystone.lua` 加载对应 ABI 的动态库，调用 C API 并返回原始机器码字节串。

## 构建

安装 Android NDK、Android SDK CMake 3.22.1，并设置 `ANDROID_HOME`。NDK 默认路径为
`$ANDROID_HOME/ndk/android-ndk-r23c`；也可以用 `ANDROID_NDK_HOME` 指定其他 NDK。
克隆本仓库时需包含 Keystone 子模块：

```powershell
git clone --recurse-submodules <仓库地址>
```

在本目录运行：

```powershell
.\build.ps1
```

脚本只构建 AArch64 和 X86 汇编后端，分别生成两个 Android ABI 的库。

## Lua 调用

把 `package/keystone` 目录复制到 `/sdcard/xiaoyv/extensions/`，在小鱼精灵扩展页导入
`keystone` 目录；将 `keystone.lua` 放入 Lua 模块搜索路径（例如脚本目录）。模块会按当前
Worker ABI 自动取得已导入的私有库路径。然后传入目标架构、起始地址和汇编文本：

```lua
local 汇编 = require('keystone')
local 字节串 = 汇编('arm64', 0x1000, 'mov x0, #100\nret')
```

`x64` 目标示例：`汇编('x64', 0x1000, 'mov rax, 100\nret')`。
返回值是原始二进制 Lua 字符串，可直接交给接受字节串的内存写入函数。

这使用小鱼运行时内置的 cffi-lua + libffi，不是 LuaJIT FFI。Android 上从可写共享存储
直接 `dlopen` 可能失败；应使用应用私有、只读的 `.so` 副本。

## 许可

Keystone 上游采用 GPLv2 或商业授权。FOSS Exception 仅覆盖符合其条件的自由及开源软件；
如将库随闭源产品发布，应先按子模块 `src/LICENSE-COM.TXT` 联系上游确认商业授权。
相关上游文本见 `src/COPYING`、`src/LICENSE-COM.TXT`、`src/EXCEPTIONS-CLIENT`；根目录 `LICENSE`
为 Keystone GPLv2 许可证副本。
