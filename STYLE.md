# Style

## Naming

- **Variables, fields, arguments:** `camelCase`
- **Constants:** `SCREAMING_SNAKE_CASE` only
- **Procs and types:** `PascalCase`

- In case of having central struct and around it wrapers that are like methods use the struct name + proc name. For example:

```odin
World :: struct {}
WorldUpdate :: proc() {}

Unit :: struct {}
UnitSetHealth :: struct {}
```

## Switches

- Prefer exhaustive switches. Do **not** use partial switches (`#partial switch`), except in very rare cases where a full switch is genuinely impossible and the omission is obvious.

## Proc wrappers

- Do not add a proc that only forwards to another proc with different/default arguments:

```odin
InnerProc(a, b: int) {}

OuterProc(b: int) { InnerProc(2, b) } // Not allowed
```

Call `InnerProc(2, b)` directly instead.

## Init/Deinit procs

- There are cases where you need to init an struct in an specific way always to work correctly. In those cases create a proc that receives a point of it. In that way you are free to allocate it on heap or stack and init it anyway

- If a deinit proc is available it always should be defered to avoid possible memory problems.

```odin
World :: struct {
	players: [dynamic]Player,
}

WorldInit :: proc(world: ^World) {
	// allocate 100 players
}

WorldDeinit :: proc(world: ^World) {
	// deallocate 100 players
}

main :: proc() {
	world: World
	WorldInit(&world)
	defer WorldDeinit(&world)
}
```

## Proc declaration

- The header of a proc should always be one line.

```odin
WrongProc :: proc(a: int,
	b: f32,
	c: bool) {}

GoodProc :: proc(a: int, b: f32, c:bool) {}
```

## Proc repeated argument types

- If two or more arguments have the same type you can type it just once

```odin
WronArg :: proc(a: int, b: int) {}
GoodArg :: proc(a, b: int) {}
```

## do's

- Use do whenever is possible in conditionals. If the line becomes extremly long, avoid it, but it should be extremly long to be avoided

## Unions whenever are possible

- Use unions whenever are possible and avoid repeated fields between structs as much as possible. You can follow this pattern:
```odin
Unit :: struct {
	position, health: f32,
	type: UnitType,
}

UnitType :: union {
	Warrior,
	Giant,
}

Giant :: struct {
	height: f32,
}

Warrior :: struct {}
```
- In case all union types are empty structs prefer using an enum

## Consts in procs

- To avoid multiple consts for different union variations of similar patterns (like each enum value) you can use a proc for runtime dispatch

```odin
BuildingType :: enum {
	hearth,
	house,
}

UnityTypeHealth :: proc(type: BuildingType) -> f32 {
	switch type {
	case hearth:
		return 20
	case house:
		return 10
	}
}
```

## Enum and union naming

- They should be in singular

```odin
// good name
BuildingType :: enum { 
	
}

// bad name
BuildingsType :: enum {
	
}

// bad name
BuildingTypes :: enum {
	
}
```

## Enums for errors

- If an error return can have different resolutions, use an enum for returning the type of it

- If the error has just a binary possible resolution, use a bool

```odin 
FindPlayerError :: enum {
	Success, // the ok ones always as firsts
	Unbound,
	Panic,
}

Example :: proc() -> FindPlayerError {return .Success}
```

## Generics

- Don't be afraid of using generics if it simplifies work
- Use generics just if the problem cannot be solved with unions or switches and it is easier to make with generics

## Static arrays lenght

- If an array is static and the lenght know at compile time use "?" instead of the explicit number
```odin
// bad
swarmCards := [2]CardDefinition{
	{"Overwhelm", .Combat, 0, "+1 strength per unit in the hex beyond the first (max +2)."},
	{"Chitin", .Combat, 0, "+2 defense this combat."},
}

swarmCards := [?]CardDefinition{
	{"Overwhelm", .Combat, 0, "+1 strength per unit in the hex beyond the first (max +2)."},
	{"Chitin", .Combat, 0, "+2 defense this combat."},
}
```

## Private 

- Avoid private structs, enums, procs, variables, consts, etc.
- Just private if they are really private, like some specific test for an specific field to avoid populating outisde package/file to avoid errors specially for a cleaner package API

## Comments

- Keep comments very short and concise.
- Comment struct fields inline, not above the field:

```odin
S :: struct {
	// Don't comment like this about a
	a: B // Comment like this
}
```

## Memory

- Do not create heap allocations that outlive the proc scope.
- Every `new`/`make` must have a matching `defer delete`/`free`, following that pattern.
