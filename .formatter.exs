locals_without_parens = [
  command: 2,
  command: 3,
  field: 1,
  field: 2,
  field: 3,
  property: 1,
  property: 2,
  property: 3,
  entity: 1,
  entity: 2,
  entity: 3,
  entities: 1,
  entities: 2,
  entities: 3,
  dispatch: 1,
  state: 1,
  transition: 2,
  event!: 2,
  event!: 3,
  event!: 4,
  event: 2,
  event: 3,
  event: 4,
  execute: 2,
  execute: 3,
  execute: 4,
  object_value: 1,
  object_value: 2
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ]
]
