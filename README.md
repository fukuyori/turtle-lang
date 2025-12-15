# 🐢 Turtle Graphics Language Interpreter

A Logo-inspired turtle graphics language interpreter implemented in Common Lisp. Draw everything from simple geometric patterns to recursive fractal art with an intuitive, educational syntax.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![SBCL](https://img.shields.io/badge/SBCL-2.0+-green.svg)
![Common Lisp](https://img.shields.io/badge/Common%20Lisp-ANSI-orange.svg)

## 🎨 Gallery

| Koch Snowflake | Binary Tree | Sierpinski Triangle |
|:---:|:---:|:---:|
| ![Koch](docs/demo-koch.svg) | ![Tree](docs/demo-tree.svg) | ![Sierpinski](docs/demo-sierpinski.svg) |

| Flower Pattern | Spiral | Color Wheel |
|:---:|:---:|:---:|
| ![Flower](docs/demo-flower.svg) | ![Spiral](docs/demo-spiral.svg) | ![Colors](docs/demo-colors.svg) |

## ✨ Features

- **Full Logo-style Syntax**: Familiar commands like `forward`, `right`, `repeat`, `to...end`
- **Arithmetic Expressions**: Use expressions like `360 / :sides` directly in commands
- **Recursion Support**: Draw complex fractal patterns with recursive procedures
- **Conditional Branching**: `if` and `ifelse` for program flow control
- **Multiple Loop Types**: `repeat`, `while`, and `for` loops
- **Lexical Scoping**: Proper variable scoping with environment chains
- **Color Support**: Customizable pen color and stroke width
- **SVG Output**: Browser-viewable vector graphics output

## 📦 Installation

### Requirements

- SBCL (Steel Bank Common Lisp) 2.0 or later
- Or any other ANSI Common Lisp implementation (CCL, ECL, etc.)

### Setup

```bash
git clone https://github.com/fukuyori/turtle-lang.git
cd turtle-graphics-lisp
```

## 🚀 Quick Start

### Basic Usage

```bash
sbcl --load turtle-lang.lisp
```

```lisp
;; Draw a square
(run-and-save "repeat 4 [forward 100 right 90]" "square.svg")

;; Run all demos
(run-all-demos)

;; Run tests
(test-all)
```

### Interactive REPL Session

```lisp
CL-USER> (run-and-save "
to polygon :sides :size
  repeat :sides [
    forward :size
    right 360 / :sides
  ]
end

polygon 6 50
" "hexagon.svg")
```

## 📖 Language Reference

### Movement Commands

| Command | Alias | Description | Example |
|---------|-------|-------------|---------|
| `forward N` | `fd` | Move forward N steps | `forward 100` |
| `back N` | `bk` | Move backward N steps | `back 50` |
| `right N` | `rt` | Turn right N degrees | `right 90` |
| `left N` | `lt` | Turn left N degrees | `left 45` |
| `home` | - | Return to origin | `home` |
| `setxy X Y` | - | Move to coordinates (X, Y) | `setxy 100 50` |
| `setheading N` | `seth` | Set heading to N degrees | `setheading 0` |

### Pen Control

| Command | Alias | Description | Example |
|---------|-------|-------------|---------|
| `penup` | `pu` | Lift pen (stop drawing) | `penup` |
| `pendown` | `pd` | Lower pen (start drawing) | `pendown` |
| `pencolor C` | `pc` | Set pen color | `pencolor "red` |
| `pensize N` | `ps` | Set pen stroke width | `pensize 3` |

### Shape Drawing

| Command | Description | Example |
|---------|-------------|---------|
| `circle R` | Draw a circle with radius R | `circle 50` |
| `arc A R` | Draw an arc of A degrees with radius R | `arc 180 30` |

### Control Structures

#### repeat (Counted Loop)

```logo
repeat 4 [forward 100 right 90]
```

#### while (Conditional Loop)

```logo
make "i 1
while [:i <= 10] [
  forward :i * 5
  right 36
  make "i :i + 1
]
```

#### for (Counter Loop)

```logo
for "i 1 10 [
  forward :i * 10
  right 36
]
```

#### if / ifelse (Conditional Branching)

```logo
if :x > 0 [forward :x]

ifelse :x > 0 [forward :x] [back :x]
```

### Procedure Definition

```logo
to square :size
  repeat 4 [forward :size right 90]
end

square 100
square 50
```

#### Procedures with Return Values

```logo
to factorial :n
  if :n <= 1 [output 1]
  output :n * factorial :n - 1
end

print factorial 5  ; 120
```

### Variables

```logo
make "count 0          ; Create/update variable
make "count :count + 1 ; Update value
print :count           ; Reference variable
```

### Operators

#### Arithmetic Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `+` | Addition | `100 + 50` |
| `-` | Subtraction | `100 - 50` |
| `*` | Multiplication | `10 * 5` |
| `/` | Division | `360 / 6` |
| `%` | Modulo | `10 % 3` |

#### Comparison Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `=` | Equal to | `:x = 0` |
| `<` | Less than | `:x < 10` |
| `>` | Greater than | `:x > 5` |
| `<=` | Less than or equal | `:x <= 10` |
| `>=` | Greater than or equal | `:x >= 5` |
| `<>` | Not equal | `:x <> 0` |

#### Logical Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `and` | Logical AND | `and :x > 0 :y > 0` |
| `or` | Logical OR | `or :x = 0 :y = 0` |
| `not` | Logical NOT | `not :flag` |

### Math Functions

| Function | Description | Example |
|----------|-------------|---------|
| `random N` | Random integer from 0 to N-1 | `random 100` |
| `sqrt N` | Square root | `sqrt 2` |
| `abs N` | Absolute value | `abs -5` |
| `sin N` | Sine (degrees) | `sin 30` |
| `cos N` | Cosine (degrees) | `cos 60` |
| `atan Y X` | Arctangent (degrees) | `atan 1 1` |

### State Reporters

| Function | Description |
|----------|-------------|
| `xcor` | Current X coordinate |
| `ycor` | Current Y coordinate |
| `heading` | Current heading (degrees) |
| `pendown?` | Whether pen is down |

### List Operations

```logo
make "colors [red green blue]
print first :colors      ; red
print last :colors       ; blue
print butfirst :colors   ; [green blue]
print item 2 :colors     ; green
print count :colors      ; 3
print fput "yellow :colors   ; [yellow red green blue]
print lput "purple :colors   ; [red green blue purple]
```

## 🎯 Example Programs

### Regular Polygons

```logo
to polygon :sides :size
  repeat :sides [
    forward :size
    right 360 / :sides
  ]
end

polygon 3 80   ; Triangle
polygon 5 60   ; Pentagon
polygon 8 40   ; Octagon
```

### Recursive Tree

```logo
to tree :size :depth
  if :depth = 0 [stop]
  forward :size
  left 30
  tree :size * 0.7 :depth - 1
  right 60
  tree :size * 0.7 :depth - 1
  left 30
  back :size
end

penup back 100 pendown
tree 80 7
```

### Koch Snowflake

```logo
to koch :size :depth
  if :depth = 0 [forward :size stop]
  koch :size / 3 :depth - 1
  left 60
  koch :size / 3 :depth - 1
  right 120
  koch :size / 3 :depth - 1
  left 60
  koch :size / 3 :depth - 1
end

to snowflake :size :depth
  repeat 3 [
    koch :size :depth
    right 120
  ]
end

snowflake 300 4
```

### Sierpinski Triangle

```logo
to sierpinski :size :depth
  if :depth = 0 [
    repeat 3 [forward :size right 120]
    stop
  ]
  sierpinski :size / 2 :depth - 1
  forward :size / 2
  sierpinski :size / 2 :depth - 1
  back :size / 2
  left 60
  forward :size / 2
  right 60
  sierpinski :size / 2 :depth - 1
  left 60
  back :size / 2
  right 60
end

sierpinski 350 5
```

### Flower Pattern

```logo
to petal :size
  repeat 60 [forward :size right 3]
  right 120
  repeat 60 [forward :size right 3]
end

to flower :size :petals
  repeat :petals [
    petal :size
    right 360 / :petals
  ]
end

pencolor "crimson
flower 2 12
```

## 🏗️ Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Source    │────▶│   Lexer     │────▶│   Tokens    │
│   Code      │     │             │     │             │
└─────────────┘     └─────────────┘     └─────────────┘
                                              │
                                              ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    SVG      │◀────│  Evaluator  │◀────│   Parser    │
│   Output    │     │             │     │     AST     │
└─────────────┘     └─────────────┘     └─────────────┘
```

### Module Breakdown

| Module | Lines | Description |
|--------|-------|-------------|
| Lexer | ~150 | Tokenizes source code |
| Parser | ~300 | Builds Abstract Syntax Tree |
| Evaluator | ~350 | Executes the AST |
| Turtle | ~100 | Manages turtle state |
| SVG Output | ~50 | Generates SVG files |
| **Total** | **~950** | |


## 🧪 Testing

```lisp
;; Run all tests
(test-all)

;; Individual tests
(test-arithmetic)   ; Arithmetic operations
(test-comparison)   ; Comparison operators
(test-recursion)    ; Recursive procedures
(test-lists)        ; List operations
(test-while)        ; While loops
(test-for)          ; For loops
```

## 🔧 API Reference

### Main Functions

```lisp
;; Execute source code
(run source-string) → interpreter

;; Execute and save to SVG
(run-and-save source filename &key width height) → interpreter

;; Convert turtle state to SVG string
(turtle-to-svg turtle &key width height) → string

;; Save turtle state as SVG file
(save-svg turtle filename &key width height)
```

### Interpreter Object

```lisp
(interpreter-turtle interp)        ; Turtle state
(interpreter-procedures interp)    ; Procedure table
(interpreter-global-env interp)    ; Global environment
(interpreter-output-buffer interp) ; Print output buffer
```


## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Logo Programming Language](https://el.media.mit.edu/logo-foundation/) - The inspiration for this project
- [UCBLogo](https://people.eecs.berkeley.edu/~bh/logo.html) - Reference implementation
- [Common Lisp](https://common-lisp.net/) - Implementation language

---

**Happy Turtling! 🐢**