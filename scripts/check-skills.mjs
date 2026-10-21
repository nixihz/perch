import { readdirSync, readFileSync, existsSync, realpathSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const isLocalTarget = target => target.length > 0 && !/^[a-z][a-z\d+.-]*:/i.test(target);

function checkStc(stc, errors) {
  const read = path => readFileSync(path, 'utf8');
  const walk = directory => readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? walk(path) : [path];
  });
  for (const file of walk(stc).filter(path => path.endsWith('.md'))) {
    for (const match of read(file).matchAll(/\]\(([^\s)]+)\)/g)) {
      const target = match[1].split('#')[0];
      if (!isLocalTarget(target)) continue;
      if (!existsSync(resolve(dirname(file), target))) errors.push(`本地引用失效：${file} → ${target}`);
    }
  }
  const cases = join(stc, 'evaluations', 'cases.json');
  // STC 已简化为文稿约定；只有保留行为用例的版本才检查用例结构。
  if (!existsSync(cases)) return;
  try {
    const data = JSON.parse(read(cases));
    if (data.version !== 1 || !Array.isArray(data.cases) || !data.cases.length) throw new Error('需要 version: 1 和非空 cases 数组');
    const ids = new Set();
    for (const item of data.cases) {
      if (!validCase(item)) throw new Error('用例缺少有效的 id、request、context、input 或 checks');
      if (ids.has(item.id)) throw new Error(`用例 ID 重复：${item.id}`);
      ids.add(item.id);
    }
  } catch (error) {
    errors.push(`STC 行为用例结构无效：${error.message}`);
  }
}

function validCase(item) {
  const nonempty = value => typeof value === 'string' && value.trim().length > 0;
  return item && ['id', 'request', 'input'].every(key => nonempty(item[key]))
    && typeof item.context === 'string' && Array.isArray(item.checks)
    && item.checks.length > 0 && item.checks.every(nonempty);
}

function checkEntry(root, name, errors, warnings) {
  const directory = join(root, 'skills', name);
  const skill = join(directory, 'SKILL.md');
  if (!existsSync(skill)) {
    errors.push(`缺少 SKILL.md：${name}`);
    return;
  }
  const metadata = readFileSync(skill, 'utf8').match(/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/)?.[1];
  if (!metadata || !new RegExp(String.raw`^name: ["']?${name}["']?\s*$`, 'm').test(metadata)
      || !/^description:\s*\S/m.test(metadata)) errors.push(`SKILL 元数据缺少匹配的 name 或 description：${name}`);
  const discovery = join(root, '.agents', 'skills', name);
  if (!existsSync(discovery)) warnings.push(`缺少或失效的本地发现入口：${name}`);
  else if (realpathSync(discovery) !== realpathSync(directory)) errors.push(`本地发现入口指向错误目录：${name}`);
}

export function checkSkills(root) {
  const errors = [];
  const warnings = [];
  const read = path => readFileSync(path, 'utf8');
  const names = readdirSync(join(root, 'skills'), { withFileTypes: true })
    .filter(entry => entry.isDirectory()).map(entry => entry.name).sort();
  const listed = [...read(join(root, 'README.md')).matchAll(/^\| `skills\/([^`]+)` \|/gm)]
    .map(match => match[1]);
  for (const name of listed) {
    if (!names.includes(name)) errors.push(`README 列出了不存在的 skill：${name}`);
    if (listed.indexOf(name) !== listed.lastIndexOf(name)) errors.push(`README 重复列出：${name}`);
  }
  for (const name of names) {
    if (!listed.includes(name)) errors.push(`README 缺少：${name}`);
    checkEntry(root, name, errors, warnings);
  }
  const claude = join(root, '.claude', 'skills');
  const agents = join(root, '.agents', 'skills');
  if (!existsSync(claude)) warnings.push('缺少或失效的 .claude/skills 入口');
  else if (!existsSync(agents) || realpathSync(claude) !== realpathSync(agents)) errors.push('.claude/skills 未复用 .agents/skills');

  const stc = join(root, 'skills', 'stc');
  if (existsSync(stc)) checkStc(stc, errors);
  return { errors, warnings, skillCount: names.length };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = resolve(process.argv[2] ?? join(dirname(fileURLToPath(import.meta.url)), '..'));
  try {
    const result = checkSkills(root);
    for (const message of result.warnings) console.warn(`警告：${message}`);
    for (const message of result.errors) console.error(`错误：${message}`);
    console.log(`结构检查：${result.skillCount} 个 skill，${result.errors.length} 个错误，${result.warnings.length} 个警告。未验证改写语义。`);
    process.exitCode = result.errors.length ? 1 : 0;
  } catch (error) {
    console.error(`无法完成结构检查：${error.message}`);
    process.exitCode = 1;
  }
}
