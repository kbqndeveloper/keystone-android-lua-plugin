-- Keystone 0.9.2 的 FFI 调用入口，返回 ARM64 或 x86_64 的机器码字节串。
-- local 汇编 = require('keystone')
-- local 字节串 = 汇编('arm64', 0x1000, 'mov x0, #100\nret')

local ffi = require('ffi')

ffi.cdef[[
typedef struct ks_struct ks_engine;
typedef unsigned long long ks_u64;
typedef unsigned long ks_size;

int ks_open(int arch, int mode, ks_engine **ks);
int ks_close(ks_engine *ks);
int ks_errno(ks_engine *ks);
const char *ks_strerror(int code);
int ks_asm(ks_engine *ks, const char *source, ks_u64 address,
           unsigned char **encoding, ks_size *encoding_size,
           ks_size *statement_count);
void ks_free(unsigned char *encoding);
]]

local 设备参数 = {
    arm64 = {'arm64-v8a', 2, 0},
    x64 = {'x86_64', 4, 8}
}

local 参数 = 设备参数[ffi.arch]
assert(参数, 'Keystone 插件只支持 arm64-v8a 和 x86_64')

local LuaEngine = import('com.nx.assist.lua.LuaEngine')
local 相对路径 = 'keystone/' .. 参数[1] .. '/libkeystone.so'
local 动态库路径 = LuaEngine.getExtensionPath(相对路径)
assert(动态库路径, '未导入 Keystone 插件：请将 keystone 目录放入扩展目录并导入')
local 库 = ffi.load(动态库路径)

local 架构参数 = {
    arm64 = {2, 0},
    arm64be = {2, 0},
    x64 = {4, 8}
}

return function(架构, 地址, 汇编文本)
        local 目标参数 = 架构参数[架构]
        assert(目标参数, '架构只能是 arm64 或 x64')
        assert(type(汇编文本) == 'string', '汇编内容必须是字符串')

        local 引擎 = ffi.new('ks_engine *[1]')
        local 状态 = 库.ks_open(目标参数[1], 目标参数[2], 引擎)
        if 状态 ~= 0 then
            error('Keystone 初始化失败：' .. ffi.string(库.ks_strerror(状态)), 2)
        end

        local 输出 = ffi.new('unsigned char *[1]')
        local 输出长度 = ffi.new('ks_size[1]')
        local 语句数 = ffi.new('ks_size[1]')
        local 成功, 结果 = pcall(function()
            状态 = 库.ks_asm(引擎[0], 汇编文本, ffi.cast('ks_u64', 地址), 输出, 输出长度, 语句数)
            if 状态 ~= 0 then
                local 错误码 = 库.ks_errno(引擎[0])
                error('汇编失败：' .. ffi.string(库.ks_strerror(错误码)), 0)
            end
            return ffi.string(输出[0], tonumber(输出长度[0]))
        end)

        if 输出[0] ~= ffi.nullptr then 库.ks_free(输出[0]) end
        库.ks_close(引擎[0])
        if not 成功 then error(结果, 2) end
        return 结果
end
