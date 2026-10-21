# language: zh-CN

@bdd
功能: 来源隔离预览
  作为能力维护者
  我希望在隔离区按固定提交预览远端来源
  以便失败时没有残留，并且预览不会直接改变收录或项目

  背景:
    假设 使用当前仓库作为能力库存
    而且 本机状态写入隔离的临时目录

  场景: 远端失败不会留下预览
    假设 远端来源不可访问
    当 尝试预览来源 "https://github.com/bdd-owner/missing"
    那么 操作失败，错误码为 "SOURCE_GIT_FAILED"
    而且 保存的来源预览为 0 个
    而且 隔离预览目录为 0 个

  场景: 预览固定到所选 commit
    假设 已准备两版本地 Git 来源
    当 以 ref "v1" 预览来源 "https://github.com/bdd-owner/skills"
    那么 预览 commit 等于第一版 commit
    而且 隔离区文件 "skills/engineering/alpha/SKILL.md" 包含 "Alpha 第一版"
    当 将标签 "v1" 移到第二版
    那么 重新读取的来源预览 commit 仍等于第一版 commit
    而且 重新读取的隔离区文件 "skills/engineering/alpha/SKILL.md" 包含 "Alpha 第一版"

  场景: 预览只写入隔离区而不收录
    假设 已准备两版本地 Git 来源
    而且 已登记项目 "demo"
    而且 已记录库存与项目快照
    当 预览来源 "https://github.com/bdd-owner/skills"
    那么 保存的来源预览为 1 个
    而且 预览候选为 1 个
    而且 隔离预览目录位于应用隔离数据
    而且 库存快照未改变
    而且 新来源未进入 catalog
    而且 项目目录未改变
