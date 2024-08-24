# semver-releaser

A simple tool to release a new software version using semantic versioning based on git repo history,
written in bash using tools installed in most Linux distributions by default.

## Basic usage

```sh
semver-releaser
```
It's going to print the suggested version of the release.

You can also run:
```sh
semver-releaser --add-git-tag
```
The script will automatically create a tag with the release version with this parameter (you can add a comment to the tag to create an annotated tag)

## List of parameters

| Parameters            | Arguments                           | Default value | Description                                                                                                                       | 
|-----------------------|-------------------------------------|---------------|-----------------------------------------------------------------------------------------------------------------------------------|
| -d  --debug-mode      | None                                | False         | Print debug message (usefully to determine why script suggests given version)                                                     |
| -s  --single-release  | None                                | False         | Raise only by the single largest version, even if there were many commits along the way that should raise the version             |
| -b  --base-release    | [major:int].[minor:int].[patch:int] | Null          | Select the base version for the release (valid only when first release) (expected format [major].[minor].[patch], example: 1.0.0) | 
| -a  --add-git-tag     | None                                | False         | Instead of printing the release version tag - add the tag in the current git repository                                           |
| -c  --comment-git-tag | [comment:string]                    | Null          | Add an annotated git tag with the given comment                                                                                   |
| -h  --help            | None                                | False         | Display help message                                                                                                              |
 
## Semantic commit prefixes that make a change  

Format: `(feat|feature|patch|fix|refactor|...) (scope optional)(!): [message]`

- feat (or feature) - use for a new feature in the code (not a tool/script) - this increment minor number
- patch (fix) - use for bug fix in the code (not a tool/script) - this increment patch number
- refactor - use when you provide a change in the code, but you don't change logic - this increment patch number
- use `!` to increment major number - that means you provide breaking change

Commit examples:

- fix: Add missing "-" in help message
- fix(script): Add missing "-" in help message
- fix (script): Add missing "-" in help message
- feature!: Add new API
    
A good example of kind of prefixes can be found [here](https://gist.github.com/joshbuchea/6f47e86d2510bce28f8e7f42ae84c716)


## Examples 

### First release
Assume your history looks like:

```
5f0a140 fix: Add missing `-` in usage_message
e27ca82 feature: allow set basic tag when no tags exist
18efa09 fix: fix logic in upgrade_biggest_semver_type
33eced6 fix: fix typo in the variable name
b68ff55 ci: Add Taskfile with basic commands
733663a feat: add git-add-tag feature
c6b894e feat: add single-release switch
c0fa822 feat: Implement basic functionality
2c0603e Initial commit
```

And you don't have any release, but you want to have it and make the release with version 1.0.0. Make: 

```shell
semver-releaser --base-release 1.0.0
```

### Multiple changes but only increment by one 

Assume your history looks like:

```
5f0a140 fix: Add missing `-` in usage_message
e27ca82 feature: allow set basic tag when no tags exist
18efa09 fix: fix logic in upgrade_biggest_semver_type
33eced6 fix: fix typo in the variable name
b68ff55 ci: Add Taskfile with basic commands
733663a feat: add git-add-tag feature
c6b894e feat: add single-release switch
c0fa822 (tag: 0.1.0) feat: Implement basic functionality
2c0603e Initial commit
```

If you run `semver-releaser` without any parameters, you will receive 0.4.1 (there are three new features and one fix)
Add the `--single-release` parameter to increment only by one number (in our case, a minor number because of the feature commit).

