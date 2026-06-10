# Mathwrap.nvim

Mathwrap.nvim formats Markdown display math source so equations are easier to read in text form without changing rendered LaTeX semantics.

## Language

**Enclosing Display Math Block**:
A Markdown display math block whose `$$` delimiters contain the current cursor position, including when the cursor is on either delimiter.
_Avoid_: nearest block, adjacent block

**Display Math Delimiter**:
A line whose non-whitespace content is exactly `$$`.
_Avoid_: inline dollars, decorated delimiter

**Math Body**:
The source text between a pair of **Display Math Delimiters**, excluding the delimiters themselves.
_Avoid_: rendered equation, LaTeX document

**Source Layout Formatting**:
Whitespace-only rewriting of a **Math Body** that improves source readability without changing rendered LaTeX semantics.
_Avoid_: semantic rewrite, rendering, previewing

**Idempotent Formatting**:
Formatting behavior where running the formatter again on already formatted source produces byte-identical output.
_Avoid_: drifting layout

**Delimiter Token Preservation**:
The invariant that formatting keeps the exact delimiter tokens written by the user while changing only source layout around them.
_Avoid_: delimiter rewrite, semantic delimiter conversion

**Soft Width Target**:
A preferred maximum source line length that guides safe split choices without forcing arbitrary breaks.
_Avoid_: hard line width, token wrapping

**Math Structure**:
A source-level mathematical unit whose layout can be considered independently during **Source Layout Formatting**.
_Avoid_: AST node, parser node, syntax tree node

**Math Command Application**:
A LaTeX math command together with the source arguments it consumes when those arguments affect source layout.
_Avoid_: text command, bare command token

**Command Argument**:
A source argument consumed by a **Math Command Application**, whether written as a braced group or as an unbraced atom.
_Avoid_: brace-only argument, arbitrary suffix

**Delimiter Group**:
A grouped math expression whose delimiter tokens are part of the rendered mathematical notation.
_Avoid_: command argument braces, syntax-only braces

**Relation Split**:
A source layout break at a configured LaTeX relation operator.
_Avoid_: equality-only split

**Equation Relation**:
A relation operator that belongs inside one equation clause, such as `=`, `:=`, `\leq`, or `\geq`.
_Avoid_: logical connector

**Logical Connector**:
A higher-level relation between equation clauses, such as `\iff`, `\implies`, or implication/equivalence arrows.
_Avoid_: equation relation

**Clause Separator**:
A source-level separator between equation clauses, including logical connectors and configured spacing commands such as `\quad` and `\qquad`.
_Avoid_: ordinary whitespace

**Atomic Spacing Token**:
A LaTeX spacing command that stays attached to adjacent source tokens, such as `\,`, `\:`, `\;`, `\!`, or escaped space.
_Avoid_: clause separator, split point

**Membership Relation**:
A relation-like operator that often binds compactly inside conditions or mappings, such as `\in`, `\sim`, or `\to`.
_Avoid_: equation relation, logical connector

**Relation Split Policy**:
The configuration choice that determines whether configured top-level relation operators are always split or only considered under width pressure.
_Avoid_: hard-coded relation style

**Bracket Expansion**:
A source layout break that expands a grouped subexpression across multiple lines.
_Avoid_: optional later feature, semantic grouping rewrite

**Layout Choice**:
One candidate source layout for a math structure, such as inline, expanded at the current structure, or expanded through selected child structures.
_Avoid_: arbitrary wrap option, rendering mode

**Internal Split Point**:
A configured source layout break candidate inside a grouped subexpression, such as a top-level additive operator, separator, or relation operator.
_Avoid_: arbitrary character wrap, length-only split

**Implicit Product Split**:
A width-pressure source layout break between adjacent multiplicative factors that are written without an explicit operator.
_Avoid_: arbitrary adjacency split, character wrap

**Leading Operator Line**:
A formatted line whose first non-whitespace token is the operator or separator that caused the split.
_Avoid_: trailing operator line

**Trailing Separator**:
A punctuation separator that remains attached to the previous item when a grouped expression expands.
_Avoid_: leading punctuation line

**Unary Sign**:
A leading `+` or `-` that belongs to a term rather than separating two additive terms.
_Avoid_: additive split operator

**Compact Atom**:
A grouped subexpression that should remain inline even when it contains punctuation or operators, such as a short interval, coordinate pair, function argument, or index condition.
_Avoid_: expandable bracket group

**Interval Atom**:
A compact bracketed endpoint pair with one top-level comma, interval-shaped delimiters, and short endpoint-like sides.
_Avoid_: arbitrary comma group, tuple

**Text Command Argument**:
The braced argument of a LaTeX text command whose internal whitespace is semantically or typographically meaningful.
_Avoid_: generic command argument

**Visible Delimiter**:
A LaTeX escaped delimiter such as `\{` or `\}` that renders as a visible delimiter and participates in source layout as a delimiter pair when paired.
_Avoid_: ignored delimiter, syntax escape

**Vertical Delimiter**:
A raw or escaped vertical bar token, such as `|` or `\|`, that can behave as a visible delimiter pair.
_Avoid_: default condition separator

**Scalable Delimiter Pair**:
A LaTeX delimiter group opened by `\left` and closed by the corresponding `\right`.
_Avoid_: unrelated left/right tokens

**Parse Failure**:
A structural ambiguity or unbalanced delimiter condition that prevents safe source layout formatting.
_Avoid_: best-effort rewrite

**Line-Bound Comment**:
A LaTeX `%` comment whose meaning depends on the original source line break.
_Avoid_: normalizable whitespace

**Math Row Separator**:
A LaTeX row break token `\\` that separates existing math rows without implying a new environment.
_Avoid_: source newline, generated aligned environment

**Alignment Marker**:
An existing LaTeX `&` marker that attaches to the nearest operator during source layout formatting.
_Avoid_: generated alignment marker, moved alignment column

**Plugin Module**:
The Lua module `mathwrap`, configured through `require("mathwrap").setup(opts)`.
_Avoid_: latex-math-source module

## Relationships

- An **Enclosing Display Math Block** is bounded by two **Display Math Delimiters**.
- `:LatexMathFormat` applies **Source Layout Formatting** to the **Math Body** of exactly one **Enclosing Display Math Block** in normal mode.
- **Source Layout Formatting** obeys **Delimiter Token Preservation**.
- **Source Layout Formatting** must be **Idempotent Formatting**.
- **Source Layout Formatting** normalizes existing line breaks and repeated spacing before applying configured split rules.
- A **Math Body** is interpreted as nested **Math Structures** before choosing source layout.
- A **Math Command Application** is a **Math Structure** when its arguments can be laid out recursively.
- A **Command Argument** may be braced or unbraced, but unbraced arguments are recognized conservatively as single obvious atoms.
- Optional **Command Arguments** are recognized only for known or configured **Math Command Applications** that declare them.
- Square brackets around an optional **Command Argument** are argument syntax, not a **Delimiter Group**.
- A **Command Argument** may mix braced and unbraced forms within one **Math Command Application**, such as `\frac a{b+c}`.
- A braced **Command Argument** is not a **Delimiter Group** just because it uses `{...}` source syntax.
- **Source Layout Formatting** preserves **Command Argument** spelling and does not add braces around originally unbraced arguments.
- `max_width` is a **Soft Width Target**; **Source Layout Formatting** never invents arbitrary breaks just to satisfy it.
- **Source Layout Formatting** includes both **Relation Splits** and **Bracket Expansion** as core formatting mechanisms.
- **Source Layout Formatting** chooses among **Layout Choices** by preferring the fewest expansions that satisfy the **Soft Width Target** when a satisfying choice exists.
- For a multi-argument **Math Command Application**, expanding only the wide **Command Argument** is preferred when that satisfies the **Soft Width Target**.
- When only a child **Command Argument** expands, its closing delimiter remains attached to the parent-line suffix when that suffix still fits.
- **Bracket Expansion** applies only when a grouped subexpression exceeds the configured width threshold, contains an **Internal Split Point**, and is not a **Compact Atom**.
- A substantial **Scalable Delimiter Pair** may expand around one child structure even when its contents do not contain an **Internal Split Point**.
- **Implicit Product Splits** apply only under width pressure and only between structural factors such as command applications, scripted scalable delimiter factors, or function-style command/delimiter factors.
- **Interval Atoms** are conservatively recognized **Compact Atoms**; uncertain comma groups fall back to normal expansion rules.
- Mixed raw paren/bracket pairs such as `(a,b]` are accepted only as **Interval Atoms**; otherwise unmatched raw delimiter shapes are a **Parse Failure**.
- Braced command arguments are eligible for **Bracket Expansion** by default; **Text Command Arguments** are excluded from normalization and expansion.
- Known math commands such as `\sqrt` and `\frac` consume layout-relevant arguments; protected text commands such as `\text` and `\operatorname` consume **Text Command Arguments** instead.
- Known command argument behavior includes built-in math commands and user-configured math commands.
- Unknown commands are treated as ordinary command tokens unless configured with argument behavior; adjacent groups may still be formatted as ordinary **Math Structures**.
- A **Text Command Argument** is an absolute formatting boundary; **Source Layout Formatting** may split around it but must not normalize or expand inside it.
- **Visible Delimiters** are rendered content but still behave as delimiter pairs for grouping and **Bracket Expansion** when paired.
- **Vertical Delimiters** are parsed as delimiter pairs when pairable and are not default split separators.
- A **Scalable Delimiter Pair** behaves as a group for relation splitting and **Bracket Expansion**, preserving each `\left` or `\right` token together with its attached delimiter; the attached opener and closer delimiters may differ.
- Expanded brackets keep the opening delimiter attached to its prefix, place internal split segments on indented lines, and place the closing delimiter on its own aligned line.
- A **Parse Failure** leaves the buffer unchanged and reports a concise error.
- A **Line-Bound Comment** outside a protected text command is a **Parse Failure** in the first version.
- **Math Row Separators** are preserved as hard row boundaries; each row is formatted independently without adding a LaTeX environment.
- Existing **Alignment Markers** are preserved as prefix decorations on the nearest operator, such as `&=` or `&\leq`; formatting does not create new alignment markers.
- The **Plugin Module** registers `:LatexMathFormat` by default and supports LazyVim-style installation with `opts = {}`.
- **Relation Splits** and **Internal Split Points** use **Leading Operator Lines**.
- Punctuation split points such as commas and semicolons use **Trailing Separators** rather than **Leading Operator Lines**.
- **Equation Relations** split inside an equation clause; **Logical Connectors** split between equation clauses and use a higher-level layout.
- **Membership Relations** are a distinct configurable split class because their layout depends more strongly on context.
- Additive operators split by default inside expanded brackets, but at top level they split only under width pressure.
- Adjacent multiplicative factors split under width pressure only when the product contains enough recognized structure to avoid splitting ordinary words or coefficients into fragments.
- Inside expanded groups, repeated top-level punctuation separators define list structure before additive operators split item internals.
- **Logical Connectors** occupy standalone clause-level lines when split.
- Spacing commands such as `\quad` and `\qquad` are treated as **Clause Separators**, not collapsed as ordinary whitespace; at the active split level, they occupy standalone separator lines.
- **Atomic Spacing Tokens** are preserved inline and are not split points.
- In an equation relation chain, the first **Equation Relation** moves to a **Leading Operator Line**, leaving the left-hand side on its own line.
- The default **Relation Split Policy** always splits configured top-level relation operators; users may configure a less aggressive policy.
- The default **Relation Split Policy** for **Membership Relations** is width-pressure based, so compact uses like `z\sim\pi`, `x\in A`, and `f:X\to Y` stay inline.
- `-` is an additive **Internal Split Point** only when it follows an operand-like token; a **Unary Sign** remains attached to its term.

## Example Dialogue

> **Dev:** "If the cursor is between two equations, should `:LatexMathFormat` pick the nearer one?"
> **Domain expert:** "No — it only formats the **Enclosing Display Math Block**; outside a block it should report that no target was found."
>
> **Dev:** "Does `$$ \tag{1}` start a display math block?"
> **Domain expert:** "No — a **Display Math Delimiter** is a standalone `$$` line."
>
> **Dev:** "Should existing line breaks inside a pasted equation constrain the output?"
> **Domain expert:** "No — **Source Layout Formatting** treats the **Math Body** as one logical expression and lays it out again."
>
> **Dev:** "Can formatting drift if the command is run repeatedly?"
> **Domain expert:** "No — **Idempotent Formatting** is a core requirement."
>
> **Dev:** "Should formatting convert `{...}` into `\{...\}` or `\left...\right`?"
> **Domain expert:** "No — **Delimiter Token Preservation** keeps the delimiter spelling the user wrote."
>
> **Dev:** "Is expanding a long bracketed expression a later enhancement?"
> **Domain expert:** "No — **Bracket Expansion** is a core part of **Source Layout Formatting**, alongside **Relation Splits**."
>
> **Dev:** "Should every long parenthesized expression expand?"
> **Domain expert:** "No — it needs an **Internal Split Point**, and a **Compact Atom** like `(-\infty, 0]` stays inline."
>
> **Dev:** "Is every two-item comma group an interval?"
> **Domain expert:** "No — an **Interval Atom** must have interval-shaped delimiters and short endpoint-like sides."
>
> **Dev:** "Is `(a+b]` a valid grouped expression?"
> **Domain expert:** "Only if it is recognized as an **Interval Atom**; otherwise the mixed raw delimiters are a **Parse Failure**."
>
> **Dev:** "Should `\frac{...}{...}` be protected from expansion just because it is a command argument?"
> **Domain expert:** "No — braced command arguments can become unreadable too; only **Text Command Arguments** get special protection."
>
> **Dev:** "If only the denominator in `\frac a{long_one + long_two} + tail` expands, should `+ tail` move to its own line?"
> **Domain expert:** "No — minimal child expansion keeps the closing `}` attached to the parent suffix as `} + tail` when that satisfies the **Soft Width Target**."
>
> **Dev:** "Should `\frac a{b+c}` become `\frac{a}{b+c}` during formatting?"
> **Domain expert:** "No — **Command Argument** spelling is preserved; command-aware parsing recognizes the application without rewriting the user's bracing."
>
> **Dev:** "Does `\{x \in A\}` create a braced group for formatting?"
> **Domain expert:** "Yes — `\{` and `\}` are **Visible Delimiters**, so they can group and expand like delimiter pairs."
>
> **Dev:** "Should `\mid` or `|` split set-builder conditions by default?"
> **Domain expert:** "No — vertical-bar tokens are delimiter-capable and should not be default separators."
>
> **Dev:** "Should `\left( ... \right)` count as grouped for split decisions?"
> **Domain expert:** "Yes — a **Scalable Delimiter Pair** is still a delimiter pair, and `\left(`/`\right)` stay attached to their delimiters."
>
> **Dev:** "Must `\left` and `\right` use the same attached delimiter?"
> **Domain expert:** "No — `\left[...\right)` is valid and still a **Scalable Delimiter Pair**."
>
> **Dev:** "Where does the closing bracket go after **Bracket Expansion**?"
> **Domain expert:** "On its own aligned line; the opening bracket remains attached to the expression prefix."
>
> **Dev:** "Should `a+b-c` format with operators at the end of the previous lines?"
> **Domain expert:** "No — use **Leading Operator Lines**, so each operator starts the term it introduces."
>
> **Dev:** "Should every short top-level sum split?"
> **Domain expert:** "No — additive splitting is default-active inside expanded brackets, but top-level additive splitting is width-pressure based."
>
> **Dev:** "Should `[a+b, c+d]` split at plus signs before commas?"
> **Domain expert:** "No — inside expanded groups, repeated punctuation separators define list items before additive splitting."
>
> **Dev:** "Should commas start continuation lines?"
> **Domain expert:** "No — commas and semicolons are **Trailing Separators**."
>
> **Dev:** "Should `a=b=c` keep `a = b` on the first line?"
> **Domain expert:** "No — the first **Equation Relation** moves to its own **Leading Operator Line**."
>
> **Dev:** "Should short relation chains still split?"
> **Domain expert:** "Yes by default, but the **Relation Split Policy** is configurable."
>
> **Dev:** "Should `a=b \iff c=d` format as one flat relation chain?"
> **Domain expert:** "No — `\iff` is a **Logical Connector** between equation clauses, while `=` is an **Equation Relation** inside each clause."
>
> **Dev:** "Are `\in`, `\sim`, and `\to` just equation relations?"
> **Domain expert:** "No — they are **Membership Relations**, with separate defaults and configuration."
>
> **Dev:** "Should `z\sim\pi` split by default?"
> **Domain expert:** "No — compact **Membership Relations** stay inline unless their layout level exceeds the width target."
>
> **Dev:** "Should `\iff` lead the next clause line?"
> **Domain expert:** "No — a **Logical Connector** gets its own clause-level line."
>
> **Dev:** "Are `\quad` and `\qquad` just spaces to collapse?"
> **Domain expert:** "No — they are **Clause Separators** in source layout."
>
> **Dev:** "Should `a=b \quad c=d` keep `\quad` inline?"
> **Domain expert:** "No — at the active split level, `\quad` occupies a standalone separator line between clauses."
>
> **Dev:** "Should `a\,b` split around `\,`?"
> **Domain expert:** "No — `\,` is an **Atomic Spacing Token** and stays inline."
>
> **Dev:** "Should `-a+b` split before the initial minus?"
> **Domain expert:** "No — the initial minus is a **Unary Sign**, not an additive split operator."
>
> **Dev:** "Can visual mode format only the middle of a long equation?"
> **Domain expert:** "No — visual and range formatting are deferred; the first version formats one normal-mode **Enclosing Display Math Block**."
>
> **Dev:** "If a single term exceeds `max_width`, should the formatter split inside the token?"
> **Domain expert:** "No — `max_width` is a **Soft Width Target**, not permission for arbitrary wrapping."
>
> **Dev:** "Should malformed delimiter structure be formatted best-effort?"
> **Domain expert:** "No — a **Parse Failure** leaves the buffer unchanged."
>
> **Dev:** "Can the formatter normalize a block containing `%` comments?"
> **Domain expert:** "No — a **Line-Bound Comment** is not safe to normalize in the first version."
>
> **Dev:** "Should existing `\\` row breaks force an `aligned` environment?"
> **Domain expert:** "No — **Math Row Separators** are preserved and each row is formatted independently."
>
> **Dev:** "Should existing `&` alignment markers make formatting fail?"
> **Domain expert:** "No — an **Alignment Marker** attaches as a prefix decoration on the nearest operator, but the formatter never creates new ones."
>
> **Dev:** "What Lua module should users configure?"
> **Domain expert:** "Use the **Plugin Module** `mathwrap`; LazyVim users should be able to install with `opts = {}`."

## Flagged Ambiguities

- "closest surrounding block" was resolved to mean **Enclosing Display Math Block**, not the nearest adjacent display math block.
- "`$$` delimiter" was resolved to mean **Display Math Delimiter**, not inline math or a delimiter line containing extra LaTeX.
- "split at top-level relation operators" was clarified as only one mechanism; **Bracket Expansion** is also core functionality.
- "relation operator" was clarified into **Equation Relations**, **Membership Relations**, and **Logical Connectors**, which have different layout levels.
