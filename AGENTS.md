# AGENTS.md — Mindustry Visual Logic

## Project identity

Godot 4.x application (GL Compatibility renderer, not Vulkan). Visual block-based logic editor for Mindustry. Open `project.godot` in the Godot editor. No npm, pip, make, or other build tools apply.

## Key commands

- **LSP**: `godot --headless --editor --lsp-server`（用哪个编辑器接都行）
- **Run**: `godot --path /home/ylxc/Projects/app/mindustry-visual-logic`, or F5 in the editor
- **Export**: 预设 Linux / Android / Windows Desktop 三套（`export_presets.cfg` 是 gitignored，换机要重配）；
  产物在 `export/<平台>/`；编辑器 UI 或 CLI 都行 —— `godot --headless --path . --export-release "<预设名>" <输出路径>`。
  Android 必须用 JDK ≤ 23（模板的 Gradle 8.11.1 跑不了 JDK 27）
- **Headless 冒烟**: `godot --headless --path . --quit-after 60` —— 加载主场景跑若干帧，能捕到脚本解析/运行期错误
- **No tests, no CI, no linter** — do not attempt to run any

## Directory layout

```
srcs/                                   ← 按职责分区：app 外壳 / pages 标签页 / windows 独立窗口 / model / defs / view / mlog
├── app/                        ← 应用外壳
│   ├── main.tscn               ← 应用入口（project.godot 的 run/main_scene 按 uid 指向它）
│   ├── main.gd                 ← @tool，顶层 UI + 菜单 + 光标
│   └── tab_rename.gd           ← 标签条就地重命名（手势 + 输入框；外壳只接"改完写到哪"）
├── pages/                      ← 标签页
│   ├── editor.tscn             ← 编辑器页场景（脚本已外置，不再内嵌 GDScript）
│   ├── editor.gd               ← [LogicEditorTab]：调色板 + 画布 + 拖拽 + 锁定 + 选择器
│   ├── document_page.tscn      ← 文档页（标签页形态：左边章节 / 右边富文本）
│   └── document_page.gd        ← 正文读 docs/{locale}/*.bbcode，不在代码里
├── windows/                    ← 独立窗口（公告 / 设置 / 关于）
│   ├── notice_window.tscn      ← 公告弹窗（textdb.online；脚本内嵌在场景里）
│   ├── notice_item.tscn        ← 公告条目（脚本内嵌在场景里）
│   ├── settings_window.tscn    ← 设置窗口（帧率上限 / UI 缩放 / 语言 / 失焦自动导出）
│   ├── settings_window.gd
│   ├── about_window.tscn       ← 关于窗（版本 / 作者 / 反馈与仓库链接）
│   └── about_window.gd
├── model/                      ← 纯数据层（无 Node、无控件，可序列化、可撤销）
│   ├── logic_node.gd           ← LogicNode：类型 + 字段值 + 各槽位的有序子节点 id
│   ├── logic_graph.gd          ← LogicGraph：画布上的若干条链；容器 = (owner_id, slot_id)
│   ├── graph_cloner.gd         ← 子树深拷贝（复制块用；引用字段表由调用方传入）
│   ├── graph_history.gd        ← 快照式撤销/重做
│   ├── graph_serializer.gd     ← JSON 存盘/读盘
│   └── app_settings.gd         ← 应用设置（帧率 / UI 缩放 / 语言 / 失焦导出）+ user://settings.json
├── defs/                       ← 定义层（块定义的类型化对象）
│   ├── block_def.gd            ← BlockDef：行/元素、导出模板、默认值、字段与槽位索引
│   ├── element_def.gd          ← ElementDef / OptionItem（各自带生效条件 when）
│   ├── export_part.gd          ← ExportPart：字面量 / 取字段 / 首个可见
│   ├── element_builder.gd      ← ElementBuilder：一种元素种类的行为契约
│   ├── block_library.gd        ← XML → BlockDef（不认识具体元素种类）
│   ├── element_registry.gd     ← 元素种类 → 构建器（defs 只问它，不枚举元素种类）
│   ├── selector_data.gd        ← 选择器候选（读 blocks/selectors/*.json）
│   └── condition/              ← when 条件子系统（单独成组：只有它需要词法/语法）
│       ├── condition_def.gd    ← ConditionDef：表达式树（求值 + 规范化回写）
│       └── condition_parser.gd ← when="…" 的词法/语法解析（只做语法，不校验字段）
├── view/                       ← 视图层（只渲染与交互，不持有拓扑真相）
│   ├── canvas/                 ← 画布与其相机
│   │   ├── editor_canvas.gd    ← EditorCanvas：图 + 撤销栈 + 视图集合（布局/跳线/占位预览各自外置）
│   │   └── editor_camera.gd    ← 相机：滚轮缩放 + 中键平移（左键留给框选）
│   ├── block/                  ← 块视图与几何契约
│   │   ├── block_view.gd       ← BlockView：一个块的控件、几何度量、背景绘制
│   │   └── block_metrics.gd    ← 块几何契约（尺寸/尾锚点/槽位锚点）
│   ├── elements/
│   │   └── element_builders.gd ← 内置元素构建器（ElementBuilder 子类 + 注册）
│   ├── layout/                 ← 布局求解
│   │   ├── layout_solver.gd    ← 纯函数布局求解（自底向上量、自顶向下摆、产出吸附锚点）
│   │   └── layout_result.gd    ← 求解结果（矩形表 + 锚点表）
│   ├── link/                   ← 跳线几何与锁定会话
│   │   ├── link_router.gd      ← 跳线路由（纯函数：谁引用了谁 → 可直接画的折线）
│   │   ├── link_layer.gd       ← 跳线层（Jump → 目标块的彩色折线 + 箭头）
│   │   └── link_controller.gd  ← 锁定会话（Jump 的目标按钮：拖到某块上松手 = 锁定）
│   ├── drag/                   ← 「在画布上按住并拖」这一类交互
│   │   ├── canvas_pointer_session.gd ← 指针会话骨架（搬块与锁定跳转目标共用）
│   │   ├── drag_controller.gd  ← 拖拽会话（调色板出块 / 画布内搬移 / 落地）
│   │   └── placement_preview.gd ← 落点占位块（拖拽时"现在放下会怎么样"）
│   └── selector_panel.gd       ← 内容选择弹窗（单位/建筑/物品/液体/传感器属性）
└── mlog/                       ← 与 mlog 文本互转（纯函数，不碰控件）
    ├── mlog_exporter.gd        ← LogicGraph → mlog 文本
    ├── mlog_importer.gd        ← mlog 文本 → 尚未入图的节点（复用导出模板反查块类型；结构块按行尾标记还原嵌套；jump 的行号按这段文本自己重新分析）
    └── mlog_text.gd            ← mlog 字符串字面量读写（与游戏 LParser 对齐）

blocks/{locale}/*.xml           ← 块定义（en_US / zh_CN；只差显示文本，见「本地化」）
blocks/selectors/*.json         ← 选择器候选（units / blocks / items / liquids / sensors）
docs/{locale}/*.bbcode          ← 应用内文档（帮助 → Document）：每页一个文件，首行章节名、其余 BBCode
assets/
├── fonts/
├── i18n/ui.csv                ← 界面文案的翻译表（keys,en,zh_CN；导入后生成 ui.<locale>.translation）
├── sprites/cursors/           ← custom mouse cursors
├── sprites/previews/          ← block/item/unit sprite previews
└── styles/main_theme.tres     ← main app theme
```

## Architecture

### 三层分离（重构定稿）

- **model 不知道视图**：`LogicGraph` 里只有「谁是谁的子节点、字段是什么值、每条链摆在画布什么位置」，
  没有控件、没有绝对坐标递归。容器统一表示为 `(owner_id, slot_id)`，成员是**有序数组**，
  顺序即数组下标，空位就是不存在 —— 没有 `_next_block`/`_last_block` 双向指针，也没有用 `null` 占位的字典项。
- **defs 不知道视图**：`BlockLibrary` 把 XML 解析成有类型的 `BlockDef`，且**不认识具体元素种类**；
  一种元素种类的全部行为（建控件 / 回填 / 默认值 / 取值校验 / 是否承载字段或槽位）都长在
  [ElementBuilder] 的子类上，由 [ElementRegistry] 注册（内置实现在 `view/elements/`）。
  导出与条件求值一律读数据层，不读控件 —— 「从控件里读值」这件事在实现里不存在。
- **view 从数据推导**：`BlockView` 是 `Control`（不是 `Container`），行位置自己给；
  尺寸由 `measure(slot_extents) -> BlockMetrics` 主动算出，位置由 `LayoutSolver.solve()` 统一求解。
  **位置绝不从绘制缓存反读**；块与块之间也没有父子关系，嵌套只体现在位置上。

### 画布是一层门面（本轮整理新增）

`EditorCanvas` 自己不写几何、预览、克隆的实现 —— 它们各有归属，画布只转发与缓存：

| 职责 | 归属 | 形状 |
|---|---|---|
| 布局求解 | [LayoutSolver] | 纯函数（图 + 度量 → 矩形/锚点） |
| 跳线几何 | [LinkRouter] | 纯函数（图 + 库 + 布局 → 折线） |
| 落点占位块 | [PlacementPreview] | 有状态；对画布只持 `Object` 弱引用（断类名环，冷加载才不报 `_init` 解析错） |
| 子树深拷贝 | [GraphCloner] | 纯数据（defs 层面的事靠 Callable 注入） |

搬块与锁定跳转目标是同一个交互的两个变体，共用 [CanvasPointerSession]（开始 / 每帧 /
落地 / 取消 / 失焦收尾 + 世界坐标、删除区、位置动没动）；子类只回答三个钩子：
哪个键落地、哪个键取消、松开事件要不要消费。**新加一个「在画布上按住并拖」的交互，继承它**。

同理，标签条的「就地重命名」手势+输入框全在 [TabRename] 里，外壳只接
「改完的名字写到哪」—— `main.gd` 不再自己管延时、双击与焦点。

### 框选 / 多选 / 整组拖动

- **选择集是 [BlockSelection]（`model/block_selection.gd`）**：纯数据、按节点 id 存、与视图解耦；
  信号 `changed`（无参）。选中态不存引用，视图销毁重建后依然有效；图换掉后由
  [SelectionController.prune] 清掉失效 id。
- **交互在 [SelectionController]（`view/canvas/selection_controller.gd`）**：画布的子节点，
  用引擎原生 `_unhandled_input` 收画布内未处理事件 —— 空白按住左键拖 = 框选
  （矩形实时命中顶层块，交画布覆盖层 [EditorCanvas.CanvasOverlay] 画），位移 < `BAND_MIN_DRAG`(6px) = 点击空白清空；
  `ctrl` 点击 = 切换、`shift` 点击 = 范围选（锚点基于视觉顺序）；点已选中的组（>1）= 整组拖动。
  [b]按下时不选中[/b]：等拖拽会话结束按位移判定（< `CLICK_MAX_MOVE` = 点击选中、≥ = 真拖动则 clear，
  放下不残留选中），与上游 v0.3 实锤的手感一致。
- **「视觉顺序」来自 [LayoutSolver.top_level_order]**（先按链摆位、再按行；巢里块不参与点选）——
  shift 范围选与组保序都用它，不要用链下标。矩形命中是 [LayoutSolver.nodes_in_rect]。
- **块按下先报选择层**：`BlockView._gui_input` 左键按下时先发 `press_requested`，选择层接管
  （ctrl/shift/组拖）就调 [method BlockView.consume_press] 拦住随后的 `drag_requested`；
  信号没有返回值，靠这个标志分流（`editor.gd` 的 `_on_canvas_press_requested` 只转发）。
- **组搬移走 [LogicGraph.move_nodes]**（任意集合按视觉顺序保序、一次撤销），
  链式搬移仍是 [method move_tail]（它在 `move_nodes` 之上多一个「同容器让位」）；
  删除任意集合是 `EditorCanvas.remove_nodes`（`remove_tail` 已是它的别名）。
  组拖复用 [DragController.start_group_from_view]，与单块共用占位预览 / 删除区 / 落点。

### 本地化（i18n）

界面支持 **English / 简体中文**，语言在 `Edit → Settings…` 里选（默认跟随系统）。

- **UI 文案**走 Godot 翻译：键表是 [code]assets/i18n/ui.csv[/code]（`keys,en,zh_CN`），导入后生成
  `assets/i18n/ui.<locale>.translation`（生成物，已 gitignore），路径注册在 `project.godot` 的
  `[internationalization] locale/translations`。
- **控件文本由 Godot 自动重译**（`auto_translate_mode`，Button / Label / PopupMenu 条目 / Window 标题 /
  FileDialog / TabBar 都支持）：[b]场景里写的是键[/b]（`text = "MENU_FILE"`），不是英文；
  属性读到的是原文，画出来才是译文。代码里动态拼的用 `tr("KEY") % [...]`。
  例外：`Window.title` 虽然也会自动重译，但为保险仍在 [method Main._apply_language] 里显式写一遍。
- **语言设置**：[member AppSettings.language]（`system` / `en` / `zh_CN`）+ [method AppSettings.active_locale]
  把 `system` 归一化（`zh*` → `zh_CN`，其余 → `en`，只提供这两套）。改设置即时生效。
- **切语言时要手动重取的东西**（[method Main._reload_localized_content]）：块定义、文档页、标签标题、
  设置窗下拉框、关于窗正文。其中 [method LogicEditorTab.reload_language] 会重载 `blocks/<locale>/`、
  重建调色板与块视图 —— [b]图与撤销栈不动[/b]，换的只是显示文本。
- **块定义**：`blocks/{locale}/*.xml`（`en_US` / `zh_CN`），翻译只改[b]显示文本[/b]：`<Text>` 内容、
  `<Item>` 显示文本、`<Kind name>`。两条硬规矩：
  1. `<Item>` 没有 `value=` 时，显示文本[b]就是导出值[/b]（[method OptionItem.value_or_text]）——
     翻译它必须同时补 `value="原文"`，否则导出会跟着变成中文；
  2. `placeholder=` / `default=` / `<Block name>` / `marker=` / `<Literal>` / 各种 `id`、`when` 一律不动 ——
     它们是默认值与标识符，改了会直接改变导出内容。
  校验办法：两套 [BlockLibrary] 各跑一遍，比对「导出模板渲染 + 字段默认值 + 候选取值 + 条件 describe +
  槽位/引用」必须逐字相同（显示文本除外），且两侧 `warnings` 都为空。
- **文档**：`docs/{locale}/*.bbcode`（`zh_CN` / `en_US`），文件名排序即章节顺序、首行章节名；
  某语言目录缺失时回落到 `en_US`。中文文档里的菜单路径写中文（`文件 → 保存`），英文写英文。
- **加一种语言**：`assets/i18n/ui.csv` 加一列 → [constant AppSettings.LANGUAGES] 加一项并接上
  `active_locale()` 的归一化 → `blocks/<locale>/` 与 `docs/<locale>/` 各来一套。

### 一次改动的数据流

1. 用户改控件 → `BlockView.commit_field()` → `EditorCanvas` 用 `GraphHistory.record()` 包住 `LogicGraph.set_field()`；
2. 图发出 `structure_changed` / `field_changed` / `reset` → 画布同步视图集合并重新求解布局；
3. 拖拽：`BlockView.drag_requested` → `DragController` 拿起"这个块 + 它后面的所有块"（各自子树跟着），
   每帧向画布要 `find_anchor()` 找落点，并在落点摆出一组**占位块**（半透明、显示真实字段值、
   不吃鼠标）指示
   "现在放下会怎么样"；插入到链中间时，插入点之后的块会被临时下移给占位块腾位置。
   跟手副本与占位块都是 `EditorCanvas.make_ghost()` 造的[b]幽灵[/b]（`preview` + 不吃鼠标 + 不写历史），
   用完交给 `EditorCanvas.release_ghost()` 归入幽灵池复用 —— 新建一棵控件树要 8~55 ms（带中文文本的
   `Label` 首次入树约 3 ms/个），是拖拽起手卡顿的唯一来源；[b]真实视图不走池[/b]（它们该被 `dismiss`）。
   用[b]开始拖拽的那个键[/b]**松开**才落地（一次撤销记录），原地松手视为没搬动；
   所以左键搬移就左键松手、右键复制就右键松手（`DragController._button`）；
   另一个键按下 = 取消（左键搬移时按右键仍然取消）。
   **拖到左侧块列表上松手 = 删除**（拿起的整串一起删，同样只记一条撤销）；
   拖到画布外其他地方/右键/Esc = 取消 —— 拖拽本身不改数据。
   拖拽期间块里的可交互控件会被统一禁用（`EditorCanvas.set_elements_enabled` →
   `BlockView.set_elements_enabled` → 构建器的 `set_enabled`）：输入框变只读并交出焦点，
   下拉 / 开关 / 选择器按钮置为 `disabled`，松手/取消后恢复。
   [b]右键在块上按下 = 复制[/b]：`BlockView.copy_requested` → `DragController.start_copy_from_view`，
   跟手的是覆盖层里的一组副本（源块既不隐藏也不移动），松手时由 `EditorCanvas.duplicate_subtree`
   一次克隆整棵子树（含槽位结构），一条撤销记录；块引用指向子树[b]内部[/b]的重映射到新节点、
   指向外部的不变。拖到左侧块列表/画布外 = 取消，原地松手 = 不动数据。
   新节点在克隆时就彼此挂好，最后由 `LogicGraph.insert_subtree` 整体入图（不会把中间态暴露给信号）。
4. 锁定跳转目标：Jump 块的目标是一个 `<JumpTarget>` 按钮（不再是手填行号的输入框）。
   在它上面按下 → `BlockView.link_requested` → `LinkController` 接管：拖到某一块上松手 = 锁定到那块，
   拖到自己/左侧块列表 = 解除，空白处松手、右键、Esc = 取消（原样不动；原地松手只算点了一下）。
   落地只写一条撤销记录（`EditorCanvas.set_link`），图发出 `field_changed` 后重算布局并重绘跳线。
   跳线由 `LinkLayer` 画：同链按「宿主 C 形块通道 + 目标 + 方向」合并母线束排轨道（跨度小的占内道、
   回跳的退外道包住内部），跨链走独立走廊过桥；颜色由目标块派生；
   悬停中的候选块由 `BlockView.set_link_highlight` 描边。目标块被删时，指向它的引用会在删除的
   同一条撤销记录里被清掉（`EditorCanvas._clear_links_to`）。

### 块定义格式（`blocks/{locale}/*.xml`）

布局与可见性都用**条件**表达，逻辑运算符只有三个：

| 写法 | 含义 |
|---|---|
| `when="mode=clear"` | 相等（`!=` 表示不等） |
| `when="mode=clear|color"` | 同一字段的多取值（`|` 右边是裸取值时沿用左边的字段） |
| `when="mode=poly|image & txt=true"` | `&` 与 |
| `when="~(mode=col & txt=true)"` | `~` 非、括号 |
| `when="find=building & group=enemy"` | 多个字段共同决定 |

字段必须显式写（没有"默认字段"）；`&&` `||` `!` `and` `or` `not` 会被明确拒绝并提示改法。
拼错字段或取值会在解析时报出来 —— 旧 `show` 白名单是静默失效的。

```xml
<Block name="Print">
  <Literal>print</Literal>                        <!-- 默认导出模板：字面量 / 取字段 / 首个生效 -->
  <Field id="content" />
  <Export when="txt=true">                        <!-- 条件化模板，第一个成立的优先 -->
    <Literal>print</Literal><Field id="content" as="string" />
  </Export>
  <Row>                                           <!-- 显式分行（取代 <Br/>） -->
    <Text id="T1">Print</Text>
    <Text id="T2" when="txt=true">"</Text>	        <!-- 元素自己的生效条件 -->
    <LineBox id="content" placeholder="frog" />   <!-- placeholder 兼作默认值，可用 default 覆盖 -->
    <Text id="T3" when="txt=true">"</Text>
    <Button id="txt" text="TXT" />
  </Row>
</Block>
```

- **导出段**：`<Literal>`（可以含空格）、`<Field id>`、`<Field id link="true">`（块引用，见下）、
  `<FirstOf ids>`（取第一个**此刻生效**的字段，都不可用时输出 `0`）、
  `<AfterSubtree/>`（本块**连巢**之后那一条指令的行号：只有导出期算得出来，`If` 靠它跳过整段巢；
  Break / Continue 也复用这一格，由导出器换成所属循环的目标行号）；
  `glue="true"` / `space_before="false"` 表示本段紧贴上一段；
  `<Field as="string">` 表示这一格是字符串（引号与转义由导出器加），
  `<Field allow_empty="true">` 表示空值不补 `0`（注释文本这类字段）：导出侧靠
  `_render_part` 把 [member ExportPart.allow_empty] 传进 `_field_text` —— 漏传的话注释块的空文本
  会被补成 `# 0`，导回来内容就变了（曾经就是这个死参数）。
  `<Item alias="…">` 让导入认出这个选项的旧名字。细节见下节。
- **行**：`<Row [when]>` 显式分行；条件不成立的行**整行不参与布局**（不占位置、不绘制）。
  `<Group when="…">` 给一串连续元素共享条件（不换行，解析时并入元素条件）。
- **元素**：`<Text>` / `<LineBox placeholder>` / `<Option>`+`<Item [value]>` / `<Button text>` / `<Selector kind>` /
  `<JumpTarget>` / `<Nest>`；条件不成立的元素既不占位置也不显示，但控件不重建（输入焦点不会被打断）。
- **排位**：`<Place when="…" after="元素 id"/>`（或 `before=`）写在元素内部，满足 `when` 时
  这个元素挪到另一个元素的后面/前面（与可见性同一次条件求值，一起重算）。不写就是书写顺序，
  与以前行为一致。`op` 的一元运算把运算符提到前面就是这么声明的（见下节）。
- **选择器（`<Selector>`）**：`<Selector id="type" kind="units" placeholder="@unit" />` —— 一个输入框
  加一个 ▾ 按钮，按下弹出图标选择弹窗（[SelectorPanel]），选中的 `@xxx` 回填进这个字段。
  弹窗是[b]铺满编辑器页的浮层[/b]：半透明遮罩（点一下即关，也因此弹窗期间点不到画布）+ 居中面板；
  Esc 也关。面板自带 StyleBoxFlat 与紧凑格子样式（主主题没有 PanelContainer/LineEdit 条目，
  主题里 Button 的 content margin 有 30，不自己带样式会把 40px 的格子撑成 115px）。
  尺寸跟着内容走（[method SelectorPanel._fit_and_center]，注意 Control 只会跟最小尺寸变大、
  不会自己缩回，所以要从宽的种类切回窄的必须显式 reset_size）。
  它是普通字段元素（`is_field`），所以导出模板、`when` 条件、校验都跟 `<LineBox>` 一样，
  互换只影响显示。
  [b]选中后必须显式提交数据层[/b]（[method BlockView.apply_picker_value]）：程序化设置
  `LineEdit.text` / `OptionButton.select()` [b]不会[/b]发 text_changed / item_selected ——
  只有用户输入才发。曾经这里指望「回填 → text_changed → commit_field」顺带提交，结果
  控件显示了新值、数据层还是旧值，导出自然还是默认值（选中单位/建筑/物品后导出没变就是这个原因）。
  候选来自 `blocks/selectors/{kind}.json`：`units`(58) / `blocks`(259) /
  `items`(22) / `liquids`(11) / `sensors`(411，带 Item/Liquid/Payload/More 分组)。
  [b]弹窗有搜索框[/b]：边打边筛（`c`、`copper`、`@copper` 都行；开头命中排最前，
  所以打 `router` 第一个就是 `@router` 而不是 `@duct-router`），回车选第一个，Esc 关掉。
  [b]只打一个 `@` 会列出全部候选[/b]：`_matches` 的第一个分支专管这件事，别当冗余删掉 ——
  `trim_prefix("@")` 之后的 needle 是空串，而 [method String.contains] 对空串恒为假。
  注意 `placeholder` 兼作默认值：只想改提示就同时写 `default=`（否则新块的默认值会被改掉）。
  目前已挂：`UnitBind.type`(units)、`UnitItem.item`(items)、`UnitBuild.block`(blocks)、
  `UnitLocate.ore`(items)、`Sensor.prop`(sensors) —— 其它要挂的字段把 `<LineBox>` 换成 `<Selector>` 即可。
- **块引用**：`<Field id="target" link="true"/>` 声明该字段存的是**另一块的引用**（`#<节点 id>`），
  而不是直接进 mlog 的文本。Jump 就是这么做的：导出时由 `MlogExporter` 把它换成目标块的**指令行号**
  （注释行 `#…` 与别人手写的标签行 `label:` 不占行号 —— **[b]标签块已经移除**[/b]：跳转目标只能用块引用，
  导入时标签行会出声跳过、`jump 标签` 按未锁定处理），导入时按[b]这段文本自己的行号[/b]把数字绑回片段内的块
  （`MlogImporter.parse` 边解析边数指令，不查当前文档的行号表 —— 否则粘贴片段时 jump 会直接连到已有的块上）。
  「哪些字段是引用」的唯一真相在导出模板上（`BlockDef.reference_fields()`），元素种类只管怎么编辑它。
- **结构块（`If` / `While`）的导出与还原**：它们没有目标字段，模板就是「比较取反的一条 `jump`」—— 条件不成立时跳过整段巢；
  取反逐项写在 `<Export when="cmp=…">` 里（`equal`→`notEqual`、`lessThan`→`greaterThanEq`…），
  没写 `when` 的那条按「相等」兜底；`strictEqual` / `always` 不在它们的可选值里（一条 jump 取反不了严格相等）。
  行号由 `MlogExporter` 算：`_walk` 给每个节点记下「子树结束的下标」，`_table_of` 再换算成 `after` 行号表。
  [b]循环还要一条尾跳[/b]：`<Tail>` 是整段巢之后补的那一行（`<SelfLine/>` = 本块头部那一行），`_walk` 把它当作
  同一个节点的第二条 entry —— 它照样占行号，但 `line_of` / `fallback` / `after` 只认头部那一条（别人 jump 到这块要落到头部）。
  [b]块定义解析器里 `export_target` 就是为它加的[/b]：`<Block>` 默认写基础模板、`<Export when>` 写变体、`<Tail>` 写尾跳
  （以前靠 `variant` 判断，加第三种目标就会写错数组）。
- **Break / Continue**：`<Block loop_jump="break|continue">` 声明它是跳出 / 继续挡板，`<Block loop="true">`（While）声明循环块。
  两者共用一条 `<Literal>jump</Literal><AfterSubtree/>…` 模板，导出器按 `_walk` 记下的「所属最内层循环」把那一格换成
  Break 的「循环之后」或 Continue 的「循环尾跳行」（`_table_of` 返回的 `loop` 表就是它），不在循环里则导出 `-1` 并警告。
  它们也带行尾标记（`#break` / `#continue`），导入据此还原；[b]标记块没有巢就不参与结构还原[/b]（`parse()` 里按 `_nest_slot` 判）。
- **导出末尾的 `stop`**：渲染完由 [method MlogExporter.export] 在末尾补一条 `stop`（`_ends_with_halt` 看最后一条指令是不是
  `stop` / `end`，后面只跟注释也算）—— 「跑出程序末尾」本来就等于停住，写明它之后，指向程序外的 jump
  （`after == count`：末尾循环的头部、跳出等）就落在这一行上，不会出现指向不存在行的 jump。空程序照旧导出空。
- **行尾标记（导入还原结构块）**：`<Block name="If" marker="if">` 声明标记后，导出时由 `MlogExporter.marker_fields`
  在行尾补一段 `#if 字段=值…`（值带空白/引号就加引号，同 mlog 字面量写法）—— 字段要写全，因为模板里的比较是
  取反导出的，从行里认不回来。标记只写在头部那一条上。导入侧 `MlogImporter` 拿它把这一行认回结构块：
  `_match(…, allow_lines=true)` 允许 `<AfterSubtree/>` / `<SelfLine/>` 那两格取到行号，`_build_structure` 按
  「没标记的行照旧」把序号区间挂回槽位，顺手数出[b]这段文本自己的行号表[/b]（指令序号 → 节点，尾跳占号但不记），
  并把结构块自己的尾跳（对得上 `<Tail>`、且 `<SelfLine/>` 就是它头部那一行）
  从结果里剔掉 —— 它由导出时重新补。[b]尾跳剔不干净 = 回跳重复一条[/b]，这是这块最容易踩的坑。
  [b]改这里要注意[/b]：`parse()` 现在会写好槽位，调用方（`editor.gd` 的两处导入）必须用 `MlogImporter.subtrees()`
  + `LogicGraph.insert_subtree` 整棵插入 —— 再逐个 `insert_node` 会把巢里的块也塞进链里。
- **`<Item value="33">!</Item>`**：显示值与导出值可以不同（PrintChar 是显示字符、导出字符码）。
- **报错要出声**：`condition_parser.gd` 只做语法解析；「字段是否存在、取值是否合法」由 `BlockLibrary`
  在整块解析完后统一校验。语法错、未知字段、非法取值、未注册的元素标签与 `<Br>`/`<Pressed>` 旧写法
  都会进 `BlockLibrary.warnings` —— 写错不会静默变成"恒生效"。
- **改格式时的安全做法**：先 dump 一遍行为快照（每个字段组合的生效元素集合 + 导出结果），
  改完再 dump 比对 —— 迁移就是这么做的（见 git 历史），它抓出过三个"解析零警告但行为已变"的 bug。

### mlog 文本格式（与官方对齐）

Mindustry 的文本读写是[b]构建期生成[/b]的（`annotations/…/LogicStatementProcessor` 生成
`mindustry.logic.LogicIO`）：写 = 语句名 + 该语句类的[b]每一个非 transient 字段[/b]（枚举用 `.name()`）；
读 = 按位置逐个赋值（`if(length > i+1)`，所以[b]短行合法[/b]、缺的参数保持默认）。
由此有三条硬约束，改块定义时不能破：

1. [b]每条语句的参数个数固定[/b]：`draw` 8、`control`/`ucontrol` 7、`radar`/`uradar` 8、`ulocate` 9、
   `op` 5、`select` 7、`sensor`/`read`/`write` 4、`getlink` 3、`packcolor`/`unpackcolor` 6……
   导出模板必须整够这么多格（用 `<Literal>0</Literal>` 占位也行）：少一格后面的参数读串位，
   多一格游戏整行判成无效语句。
2. [b]同一格的含义随选项变[/b]：`draw` 的六格是官方的 (x, y, p1…p4)，哪个字段落在哪一格看 `mode`
   （`LExecutor`/`LogicDisplay`：`rotate` 的角度在 [b]p1[/b]、`print` 的对齐在 p1、`rect` 的宽高在 p1/p2…）；
   `ucontrol` 的 p1…p5 也随类型变（`itemDrop` = 目标+数量，`itemTake` = 目标+物品+数量）。
   这类块用一串 `<FirstOf>` 把「当前模式生效的那个字段」放进对应格子 —— 顺序写错，
   值就落进游戏不读的参数里（表现就是“改一下选项，内容就变了/丢了”）。
3. [b]枚举取值必须是官方的 Java 名[/b]（`col`、`lineRect`、`payTake`、`autoPathfind`…）：
   否则游戏那边 `valueOf()` 抛异常，整行变成无效语句。

导入侧（`MlogImporter`）三条对应规则：

- 结构匹配之外还按[b]选项取值合法性打分[/b]（`_score`）：`ucontrol` 的十几个变体共用 `ucontrol`
  首 token、模板结构也一样，只看结构会把 `ucontrol boost …` 绑给「移动」那块。
- `<FirstOf>` 那一格按[b]已解析出的选项值[/b]挑生效字段（与导出同一套 `is_field_active`）。
- 允许短行，并像 `LParser` 那样把 `;` 当语句分隔符、把 `#` 当行尾注释（`split_statements()`）——
  行尾那个 `#` 在 LParser 里读完就丢，所以结构块的字段快照可以放心写在那里（指令本身不受影响）。

[b]显示层与文本层是两回事[/b]：参数个数固定说的是[b]文本[/b]，界面上该藏的输入框照样要藏。
官方 UI 在每个语句的 `build()` 里按当前选项决定显示哪几个输入框，那张表就是：

- `ucontrol`：[b]`LUnitControl.params`[/b]，逐项声明的（`move("x","y")`、`approach("x","y","radius")`、
  `targetp("unit","shoot")`、`payTake("takeUnits")`，而 `idle`/`stop`/`autoPathfind`/`payDrop`/
  `payEnter`/`unbind` 没有参数）。
- `control`：`LAccess.params`（`enabled("to")`、`shoot("x","y","shoot")`、`shootp("unit","shoot")`、`config("to")`、`color("to")`）。
- `draw`：`DrawStatement.build()` 的 `switch(type)`。
- `jump` / `select`：`addOp()` 里的 `if(op != always)` —— `always` 时[b]两个比较值都不显示[/b]。
- `op`：`LogicOp.unary`（`not`/`abs`/`sign`/`log`/`log10`/`floor`/`ceil`/`round`/`sqrt`/`rand`/`sin`/
  `cos`/`tan`/`asin`/`acos`/`atan`）只显示一个操作数；[b]连顺序也变[/b] ——
  `OperationStatement.rebuild`：一元与函数型（`max`/`min`/`angle`/`angleDiff`/`len`/`noise`）
  是 `result = op a [b]`（运算符在前），其余是 `result = a op b`（旧实现用 `move_child` 挪的那个）。
- `ulocate`：`switch(locate)`；其中 `building` 这个[b]输出[/b]在 `ore` 以外的三种都有（`if(locate != ore)`）。

所以 XML 里 Row 的每个输入框都要带 `when`，而导出模板里的 `<Field>` 保持无条件 ——
两者分开写：模板负责文本，元素负责显示。改完块定义要同时跑两套检查（只跑一套就会
出现“文本对了但界面多/少一个框”或反之）。

[b]顺序随选项变就用 `<Place>`[/b]：元素只写一遍，排到哪儿交给条件 ——
以前只能把一个字段写两遍（两边条件互补）把位置“顶”出来，字段名就会在 XML 里重复，
列表类元素（`Option`）更是得整份候选值抄一遍。现在：

```xml
<LineBox id="a" placeholder="a">
  <Place when="ops=not|abs|…" after="ops" />   <!-- 一元：挪到运算符后面 -->
</LineBox>
<Option id="ops">…</Option>
<LineBox id="b" placeholder="b" when="…" />
```

规则在整块解析后统一校验：目标得存在、得同行、不能指向自己，写错会进 `BlockLibrary.warnings`。
[b]视图仍按元素建控件[/b]（`_element_entries`）：万一真把一个字段写了两遍（同一 id 两个元素），
两边的控件写的是同一份数据、各按自己的条件显隐，切选项时值不会丢；
但 `BlockDef.element(id)` / `_by_id` 只认[b]第一个[/b]，所以别把不同默认值/不同候选集的元素
放在同一个 id 上 —— 要改顺序就用 `<Place>`。

校验手段（改完 XML 跑一遍，[b]文本与显示各一条[/b]）：

- 文本：每块导出一行，token 数应与官方表一致；再逐选项导出，[b]参数个数不能变[/b]
  （选项只换内容，不换参数个数）；以及导出→导入→再导出的往返比对。
- 显示：对每个块 × 每个选项取值，拿 [method BlockDef.is_element_active]（视图用的同一函数）
  算出「可见的输入框」集合，与上面那张官方表逐个对比 —— 只做文本检查的话，
  界面多一个/少一个框这类问题根本测不出来。


### 扩展点

- 新增元素类型：在 `view/elements/element_builders.gd` 里继承 `ElementBuilder` 写一个子类并注册，
  **只改这一处**：解析、条件校验、默认值灌入、`BlockView` 与 `BlockDef` 都不用动
  （它们只问构建器：`is_field` / `is_slot` / `validate_value` / `default_value` / `apply_value` /
  `set_enabled`）。
- 新增块：往 XML 里加 `<Block>`，不需要写 GDScript。
- 新增选择器候选：改 `blocks/selectors/*.json`。
- **新增脚本放哪（按职责，别往兜底目录里塞）**：纯数据 → `model/`；块定义/条件/类型化对象 → `defs/`
  （只有一个子系统需要词法/语法时才开子目录，如 `defs/condition/`）；画布上的渲染与交互 → `view/`，
  再按机制选 `canvas` / `block` / `elements` / `layout` / `link` / `drag`；与 mlog 文本互转 → `mlog/`；
  标签页（带 [TabContainer] 的页面）→ `pages/`；独立弹窗 → `windows/`；顶层外壳（菜单/光标/标签条）→ `app/`。
  **成对的 `.tscn` + `.gd` 必须放在同一目录**（场景按相对路径找脚本时靠 uid，但同目录才好找）。


### Other

- **`@tool`**：`main.gd` 在编辑器里也会跑，但它碰的子场景（`SettingsWindow` / `LogicEditorTab`）脚本[b]不是[/b]
  `@tool` —— 在编辑器里是占位实例，读属性、接信号、调方法都会报 `placeholder instance` 错。
  相关几处（`wSettings.setup` / 两个信号连接 / `new_editor` 里的 `name_changed`）都用
  `Engine.is_editor_hint()` 挡着，别删；`_apply_settings()` 也据此直接 return（免得改掉编辑器自己的帧率/缩放/语言）。
- **`class_name`**：模型/定义/视图三层的类都全局注册。
- **公告窗**：`notice_window.tscn` 通过 HTTPRequest 拉 `https://textdb.online/MindVisualLogic`。
- **自定义光标**：`main.gd._ready()` 从 `assets/sprites/cursors/` 装载。
- **顶部工具栏**：左边是 `File`（新建页 / 存 / 开 / 导出到剪贴板 / 剪贴板导入）、
  `Edit`（撤销 / 重做 / 清空 / 设置…，弹出前按当前页状态置灰）、`Help`（文档 / 公告 / 关于）；
  右边是独立的 `Quit` 按钮（`UI._on_sort_children` 里右对齐：先量行高，再按它的宽度把菜单栏缩回去）。
  Help 里的「文档」是标签页（[DocumentPage]，开过就切过去、不重复开），
  「公告」与「关于」是独立窗口（[AboutWindow] 的版本号与引擎版本是运行期读的）。
  「清空」走 `LogicEditorTab.clear_graph()`，算一条可撤销记录；`new_project()` 则是
  「换成另一个文档」，会连撤销栈一起清掉 —— 两者不要混用。
  菜单 id 就是 `item_N/id` 的顺序编号，加删菜单项时记得同步 `_on_*_id_pressed` 里的注释。
  文档页[b]不是[/b] [LogicEditorTab]，所以在它上面「存 / 导出 / 撤销」都是空操作
  （`_current_editor()` 返回 null，编辑菜单据此置灰）—— 这不是 bug，别把菜单项接死。
- **应用内文档（帮助 → Document）**：正文是 [code]docs/{locale}/*.bbcode[/code]（[b]每页一个文件[/b]、每种语言一套）——
  文件名排序就是章节顺序，首行是章节名、其余是 BBCode 正文；加一页 = 往对应语言目录丢一个文件，
  代码不用动（[DocumentPage] 在 `_ready` 与切语言时各读一次）。
  [b]导出时必须把 [code]docs/[/code] 加进 export preset 的「Filters to export non-resource files/folders」[/b]：
  `.bbcode` 不是 Godot 资源，漏了它打包出来的应用里文档是空的（此时页面会显示提示文字）。
  同理 [code]exclude_filter[/code] 要排掉 [code]build/*[/code] 与 [code]export/*[/code]：`export_filter=all_resources`
  会把这两个目录里的 `.tres`/`.res` 一并打进包 —— 脚手架与缓存混进发行包（实测 3.2MB）。
- **F5 快捷导出**：等价于 `File → 导出到剪贴板`。键位在 [code]project.godot[/code] 的 `[input]` 里，
  action 名沿用旧版的 `compile`（旧版把「导出 mlog」叫 compile），代码里只认
  `Main.QUICK_EXPORT_ACTION` 常量 —— 要换键就改 project.godot，不用碰代码。
  实际按下时是菜单栏先把菜单项的 accelerator 接走（菜单里因此看得见 F5），
  `_unhandled_key_input` 只是焦点不在菜单栏时的兜底；两者不会双触发（前者会标 handled）。
  导出无内容（当前页是文档页等）时在 [method Main._export_to_clipboard] 里统一提示一声，
  菜单项与 F5 共用这一个出口，别再各写一份。
- **Ctrl+C / Ctrl+V**：也是 `project.godot` 里的动作（`copy_mlog` / `paste_mlog`），
  代码只认 `Main.QUICK_COPY_ACTION` / `QUICK_PASTE_ACTION`。
  [b]这两个不入菜单[/b]：菜单项的 accelerator 只有一根（F5 已经占着），而且 Ctrl+C/V 得先
  让输入框拿到（在 LineEdit 里它们就是普通的复制/粘贴文字）—— 所以它们走
  [method Main._unhandled_key_input]：输入框有焦点时根本到不了这里，在空白处按才是整页操作。
  Ctrl+C 就是导出（同一个出口，所以也只导出入口块那条链）；
  Ctrl+V 走 [method LogicEditorTab.paste_mlog_new_chain]：把剪贴板转成块、[b]另起一条链[/b]
  摆在现有内容下方（空隙 [constant LogicEditorTab.PASTE_GAP]，靠 [method EditorCanvas.content_rect]
  算出「现有内容」），[b]不接到入口块那条链上[/b] —— 所以它不会被导出，要接上去得自己拖。
  这与 File 菜单里那两个导入项[b]不是[/b]一回事（那两个是接进入口链的），
  行号不按插入点偏移：两个入口都按这段文本自己的指令序号绑跳转 —— 片段自成一体，不会连到已有的块上。
- **入口块（Start）**：XML 里 `<Block entry="true">`，它所在的类别用 `<Kind hidden="true">` 藏起来
  （Special 就是：块还在库里、`BlockLibrary.entry_def()` 找得到，只是不进调色板）。
  新页由 [method EditorCanvas.spawn_entry_block] 自动放一个，[b]不进撤销栈[/b]。
  一个文档只该有一个，所以：不能复制（[DragController.start_copy_from_view] 连会话都不开，
  [method EditorCanvas.duplicate_subtree] 再兜一道）、不能删除（拖到左侧列表时
  `_carries_entry()` 拦下）；`is_empty()` [b]不算[/b]入口块，否则「清空」永远不置灰。
  [b]导出只走入口块那条链、从它开始[/b]（[method MlogExporter._walk]）：它前面的块与
  其他链都不导出；它自己渲染成空行、不占行号（跳到它身上的 jump 落到下一条指令）。
  没有入口块就什么都不导出。
  「清空 / new_project / 剪贴板 Load」都要把入口块放回来，Load 还要把导入的块插到
  入口块那条链上 —— 插到别的链等于导不出来（见 `LogicEditorTab._import_target()`）。
- **应用设置**：`AppSettings`（`model/app_settings.gd`）是纯数据 + `user://settings.json`（容错读、超范围钳制）；
  `SettingsWindow` 只管「值 ↔ 控件」，[b]应用[/b]（`Engine.max_fps` / `root.content_scale_factor`）在 `main.gd`。
  改动即时生效、关闭窗口时才写盘；`@tool` 下 `_apply_settings()` 直接 return，
  免得在编辑器里顺手改掉 Godot 编辑器自己的帧率与界面缩放。
  「失焦自动导出」走 `main.gd._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)`（旧实现叫 compile_when_close）：
  这个通知在桌面与移动端都实现，语义正是「焦点离开本程序」；[b]不要[/b]连 `NOTIFICATION_WM_WINDOW_FOCUS_OUT`
  一起监听 —— 切到本程序自己的另一个窗口时它也会发，那会重复导出。默认[b]开[/b]（切窗口丢进游戏是主要用法），
  空程序 / 当前页不是编辑器时不动剪贴板（不能把用户刚复制的东西清掉）。
  窗口[b]自带 StyleBoxFlat[/b]（与公告窗同一套配色）：主主题只覆盖了 Button/Label/MenuBar/
  PopupMenu/TabContainer/Tree/ScrollBar，`CheckButton`/`LineEdit`/`HSlider` 会顶引擎默认皮肤。
  数值用 `LineEdit` 而不是 `SpinBox`——SpinBox 的样式长在它内部的 LineEdit 与箭头按钮上，
  override 到不了里面；这两类控件的字体也要显式 override（主题里没有它们的 font 条目）。
  窗口尺寸必须放得下内容最小宽度（`Body.get_combined_minimum_size()`），
  否则 VBox 会被压扁、左侧与底部文字直接被切掉。
- **标签页标题**：`LogicEditorTab.display_name()` 先看手动命名（`custom_name`），再跟随文件名。
  重命名是就地编辑：标签条上浮一个 `LineEdit`（TabBar 的子节点，不会变成新页面），
  单击[b]已选中[/b]的标签（延迟一个双击间隔才开，免得双击时闪一下）或[b]右键[/b]任意标签打开；
  [b]双击[/b]任意标签 = 关闭该页（关掉最后一个会自动补一个空白页）；按住拖动（重排标签）
  会取消这次改名。回车/失焦提交、Esc 取消、空名字回落文件名，切页时也会自动提交。
  实现上用 TabBar 的 `gui_input` 而不是 `tab_clicked` 信号：后者是在[b]内建处理之后[/b]才发的，
  那时当前页已经切过去了（分不出「切页」与「点已选中的页」），也拿不到 `double_click`。
  这一整套（延时、双击、输入框、提交/取消）都在 [TabRename]（`app/tab_rename.gd`）里，
  `main.gd` 只接「改完的名字写到哪」（[method Main._on_tab_renamed]）与「关掉哪一页」。

## Conventions and gotchas

- **`build/`（临时脚本、构建脚手架）、`export/`（导出的发行包）与 `export_presets.cfg` 是 gitignored**。
- **`old/`（旧版实现）已于 2026-10-11 删除**：重构早已定稿，它又不曾在 git 里 —— 再要对照旧行为
  只能看 git 历史或 GitHub 上 0.2.3 的发行版。
- **只用 GDScript**。
- **XML 块文件是块定义的唯一来源** —— 改块就是改 XML，不要改 GDScript。
- **注释只写「代码里看不出来的东西」**：不变量、顺序/耦合约束、外部格式依赖、会踩坑的行为，
  再加关键取舍的一句理由。历史叙述（「旧实现…」）、对代码的字面复述、长篇推导都别写 ——
  它们归 [code]AGENTS.md[/code] 管；改代码时顺手把注释压到 1~3 行。
- **改模型/视图后跑一次 headless 冒烟**：`godot --headless --path . --quit-after 60`。
- **GDScript 的 lambda 按值捕获**：不要在闭包里给外部变量赋值再读它（撤销栈的记录就踩过这个坑）。
- **撤销/读档会整体替换图**：`LogicGraph.load_dict()` 复用同 id 的节点对象，外部引用不会失联，
  但仍应在 `reset` 之后重新取节点。
- **拖拽控制器不要消费 mouse-up**：画布是 SubViewport，而 `SubViewportContainer` 靠
  `is_input_handled()` 决定要不要把事件转发进去 —— 一口吞掉 mouse-up，画布里那层 GUI 的
  鼠标焦点与按键掩码就清不掉，之后的左键按下会被发到残留的那个块上（鼠标不在它身上时
  `_has_point` 为假 → 表现为“拖不动任何块”，要点一下别处才恢复）。所以搬块结束只调
  `_finish_session()`，**不要**消费松开事件 —— 这条规矩现在写在
  [method CanvasPointerSession._consumes_release] 上（默认 false；锁定跳转目标确实需要消费，
  它覆写为 true 并因此要手动复位按钮的按下态）。“另一个键按下 = 取消”可以继续消费，
  因为它不会留下掩码。
  收尾事件真丢了（切窗口 / 在窗口外松手）时，由会话骨架的
  `_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)` 统一收尾（搬块与锁定目标都有）。
  也不要拿 `Input.is_mouse_button_pressed` 做守时兜底：触屏（项目有 Android 导出）不反映鼠标键。
- **UI 配色统一在 `UiStyle`（`srcs/view/ui_style.gd`）**：设置窗/公告窗/文档页/
  选择器面板的深色 `StyleBoxFlat` 全部由它构造，场景里不再内联 StyleBox（主主题
  `assets/styles/main_theme.tres` 只覆盖了 Button/Label/MenuBar/PopupMenu/TabContainer/Tree/ScrollBar）。
  改色只改 `UiStyle` 一处，各窗口自动同步。
