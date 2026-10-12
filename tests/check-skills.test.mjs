import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { checkSkills } from '../scripts/check-skills.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'skill-check-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const write = (path, content) => {
    mkdirSync(join(root, path, '..'), { recursive: true });
    writeFileSync(join(root, path), content);
  };
  write('README.md', '| `skills/stc` | 文稿改写 |\n');
  write('skills/stc/SKILL.md', '---\nname: stc\ndescription: 中文技术文稿\n---\n[规则](references/rules.md)\n');
  write('skills/stc/references/rules.md', '# 规则\n');
  write('skills/stc/agents/openai.yaml', 'interface:\n  display_name: STC\n');
  const item = { id: 'scope', request: '改写', context: '', input: '仅管理员可写入。', checks: ['保留仅管理员。'] };
  write('skills/stc/evaluations/cases.json', JSON.stringify({ version: 1, cases: [item] }));
  mkdirSync(join(root, '.agents/skills'), { recursive: true });
  mkdirSync(join(root, '.claude'), { recursive: true });
  symlinkSync('../../skills/stc', join(root, '.agents/skills/stc'));
  symlinkSync('../.agents/skills', join(root, '.claude/skills'));
  return { root, write, item };
}

test('完整目录、发现入口和引用通过结构检查', t => {
  const { root } = fixture(t);
  assert.deepEqual(checkSkills(root), { errors: [], warnings: [], skillCount: 1 });
});

test('目录表遗漏和失效引用分别报错', t => {
  const { root, write } = fixture(t);
  write('README.md', '# 空目录表\n');
  write('skills/stc/references/rules.md', '[不存在](missing.md)\n');
  const { errors } = checkSkills(root);
  assert.equal(errors.length, 2);
  assert.ok(errors.some(message => message.includes('README 缺少：stc')));
  assert.ok(errors.some(message => message.includes('missing.md')));
});

test('重复用例 ID 不会被当作额外覆盖', t => {
  const { root, write, item } = fixture(t);
  write('skills/stc/evaluations/cases.json', JSON.stringify({ version: 1, cases: [item, item] }));
  assert.ok(checkSkills(root).errors.some(message => message.includes('用例 ID 重复')));
});

test('缺少发现链接警告，指错目录报错', t => {
  const { root } = fixture(t);
  const link = join(root, '.agents/skills/stc');
  rmSync(link);
  assert.deepEqual(checkSkills(root).warnings, ['缺少或失效的本地发现入口：stc']);
  symlinkSync('../../skills', link);
  assert.ok(checkSkills(root).errors.some(message => message.includes('指向错误目录')));
});