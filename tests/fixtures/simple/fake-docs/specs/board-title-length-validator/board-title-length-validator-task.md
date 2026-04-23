# Board Title Length Validator — Task

## Definition of Done

- [ ] `BoardTitleLength` constraint class created with `min=1`, `max=200`
- [ ] Custom validator registered via Symfony attribute target `PROPERTY`
- [ ] DTO annotation replaced in `BoardTitleDto::title`
- [ ] Unit test covers: 0 chars, 1 char, 200 chars, 201 chars, whitespace-only
- [ ] `make test-unit` green
- [ ] PHPStan level 9 clean
- [ ] PHP CS Fixer clean
