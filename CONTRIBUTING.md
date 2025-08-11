# Contributing to ChronoModel

Looking to contribute something to ChronoModel? **Here's how you can help.**

## Reporting issues

We only accept issues that are bug reports or feature requests. Bugs must be isolated and reproducible problems that we can fix within the ChronoModel core. Please read the following guidelines before opening any issue.

1. **Search for existing issues.**
2. **Create an isolated and reproducible test case.**
3. **Include a live example if possible.**
4. **Share as much information as possible.** Include at least Rails version and gem version. Also include steps to reproduce the bug.

## Key branches

- `master` is the latest, deployed version and the main development branch.

## Pull requests

- All pull requests should be made against the `master` branch
- Try not to pollute your pull request with unintended changes--keep them simple and small
- **Test.** If you find a bug, write at first a failing test case and then fix it.
- We are open to discussion. If you have troubles or questions, feel free to start a new issue

## Coding standards

### Ruby

- [Ruby Style Guide](https://github.com/rubocop/ruby-style-guide)
- This project uses RuboCop to enforce code style. Run `bundle exec rubocop` to check your code.

### Testing

- This project uses RSpec for testing
- Run the test suite with `bundle exec rspec`
- Ensure all tests pass before submitting a pull request
- Write tests for new features and bug fixes

### Commits

- [How to Write a Git Commit Message](https://cbea.ms/git-commit/#seven-rules)

## License

By contributing your code, you agree to license your contribution under the terms of the [MIT License](LICENSE)