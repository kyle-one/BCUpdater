# Prompt Templates

## `repair_by_contract`

~~~~text
# Role and Task:
You are an expert in smart contracts, and your task is to fix compilation errors caused by third-party library updates based on smart contracts.
# Smart Contract: 
``` solidity
{smart_contract}
```

Please analyze the reason and provide the complete repaired code in the form of code blocks

Please note to follow the following rules
1. The contract code fragment needs to be fixed. Please strictly follow the input code for repair and do not add/complete the code arbitrarily.
2. If the input code snippet has an "import" section, it can be modified; If there is no "import" section, please do not casually complete or add the import library.
3. Please focus on the error parts and do not casually modify irrelevant parts.
4. Do not arbitrarily complete or modify the SPDX license.

Please reply according to the following template

# Analysis of Error Causes
...

# The complete contract after repair
```solidity
code...
```

# Main modifications
...
~~~~

## `get_error_line_idx`

~~~~text
I am debugging text.sol. Please help me pinpoint the exact line where the error occurs and output the line number as a number only. No additional content is needed.
{error_message}
~~~~

## `repair_by_compile`

~~~~text
# Role and Task:
You are an expert in smart contracts, and your task is to fix compilation errors caused by third-party library updates based on smart contracts and error messages.
Compile the error message and corresponding error location in the contract with comments: starting with//<error start>and ending with//<error end>.
Please remove all comments related to error messages(e.g.://<error start>, //<error end>) when generating code.

# The smart contract to be fixed:
{smart_contract}

# Error Message: 
{error_message}

Please analyze the reason and provide the complete repaired code in the form of code blocks


Please reply according to the following template

# Analysis of Error Causes
...

# The complete contract after repair
```solidity
code...
```

# Main modifications
...
~~~~

## `repair_by_compile_changelog`

~~~~text
# Role and Task:

You are an expert in smart contracts,You are fixing the contract to adapt to the latest version of Solidity and the latest third-party libraries, and your task is to fix compilation errors caused by third-party library updates based on smart contracts and error messages.
Compile the error message and corresponding error location in the contract with comments: starting with//<error start>and ending with//<error end>.
Please remove all comments related to error messages(e.g.://<error start>) when generating code.

Note:
Please don't generate other code or complete other code that is unrelated to the error.
If the input is a contract snippet, please focus on the repair of this contract and don't complete the import libraries or generate a new contract.
If the input is an import snippet, then focus on repairing the import snippet.

# The code snippets of the smart contract to be fixed:
{smart_contract}

# Error Message:
{error_message}

# Changelog Information
{changelog_information}

Please analyze the reason and provide the complete repaired code in the form of code blocks
Please reply according to the following template
# Analysis of Error Causes
...

# The complete contract after repair
```solidity
code...
```

# Main modifications
...
~~~~

## `get_search_keywords`

~~~~text
I am checking the changlog in the reference library for the purpose of fixing the code. Please generate several search keywords for me based on the compilation error message.
The error message is as follows:

# Error Message:
{error_message}

# Examples and Requirements :
For example, '@openzeppelin/contracts upgradeable/security/PausableUpgradeable.sol' should be searched for keywords such as 'PausableUpgradeable', 'Pausable', and 'security'. 
Please be careful not to include the suffix '. sol'. 
Please only include a single keyword, do not include a path.
Please output keywords that are strictly related to error messages, and do not output generic keywords.
Please use the Python code block```python```to output the results.

Please output in the following format:
# Thinking Path
# Keyword List
``` python
["keyword1", "keyword2"]
```
~~~~
