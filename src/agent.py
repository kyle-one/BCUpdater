
import json
import random
import time
import requests
import re
import os
import subprocess
import tiktoken
import logging
import sys
current_dir = os.getcwd()
sys.path.append(os.path.join(current_dir, 'static_analysis'))
from SolidityParser import parseFile
from SolidityParser import parseString

prompt_template = {}

prompt_template["repair_by_contract"] = """
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
..."""

prompt_template["get_error_line_idx"] = """
I am debugging text.sol. Please help me pinpoint the exact line where the error occurs and output the line number as a number only. No additional content is needed.
{error_message}
"""

prompt_template["repair_by_compile_old"] = """
# Role and Task:
You are an expert in smart contracts, and your task is to fix compilation errors caused by third-party library updates based on smart contracts and error messages.
# Smart Contract: 
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
..."""

prompt_template["repair_by_compile"] = """
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
..."""

prompt_template["repair_by_compile_changelog_old"] = """
# Role and Task:
You are an expert in smart contracts, and your task is to fix compilation errors caused by third-party library updates based on smart contracts and error messages.
# Smart Contract: 
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
```"""

prompt_template["repair_by_compile_changelog"] = """# Role and Task:

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
"""

prompt_template["repair_by_compile_changelog_input_file"] = """# Role and Task:

You are an expert in smart contracts,You are fixing the contract to adapt to the latest version of Solidity and the latest third-party libraries, and your task is to fix compilation errors caused by third-party library updates based on smart contracts and error messages.
Compile the error message and corresponding error location in the contract with comments: starting with//<error start>and ending with//<error end>.
Please remove all comments related to error messages(e.g.://<error start>) when generating code.

Note:
Please don't generate other code or complete other code that is unrelated to the error.

# The smart contract to be fixed:
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
"""

prompt_template["get_search_keywords"] = """
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
```"""

api_url = 'https://www.api.openai.com/v1/chat/completions'
api_keys = ["",
            ]

class ContractAgent:
    def __init__(self,contract_path):
        self.contract_path = contract_path
        self.init_contract = self.read_contract(contract_path)
        self.now_contract = self.init_contract
        self.contract_update_list = []
        #If the repair is successful, then repair_flag = True.
        self.repair_flag = False
        self.sum_input_num_tokens = 0
        self.sum_output_num_tokens = 0
        self.input_num_tokens = 0
        self.output_num_tokens = 0
        self.start_timestamp = time.time()
        #Each contract_update_list contains dictionaries like this.

        self.example_dict = {
            "contract":"xxx",
            "compile_result":"xxx",
            "error_line":"xxx",
            "update_function":"C/CR/N", #C=compile, CR=compile+RAG, N=Nothing
            "prompt":"xxx",
            "RAG_str":"xxx"}

    def remove_comments(self,text):
        text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
        text = re.sub(r'//(?! SPDX-License-Identifier:).*', '', text)
        text = re.sub(r'\n\s*\n', '\n', text)
        return text

    def replace_version(self,contract, solc_version):
        contract_lines = contract.split("\n")
        num_SPDX = 0
        for idx,line in enumerate(contract_lines):
            if "pragma solidity" in line and num_SPDX < 2:
                contract_lines[idx] = "pragma solidity ^{};".format(solc_version)
            if "// SPDX-License-Identifier:" in line:
                num_SPDX += 1
            if num_SPDX == 2:
                contract_lines = contract_lines[:idx]

        self.now_contract = "\n".join(contract_lines)
        self.now_contract = self.remove_comments(self.now_contract)
        return "\n".join(contract_lines)

    def get_small_version(self,contract):
        """
        :param contract: Contract string
        :return: String of the minimum Solidity version
        """
        contract_lines = contract.split("\n")
        for line in contract_lines:
            if "pragma solidity" in line:
                match_gl_g = re.search(r'>=([\d\.]+)', line)
                match_gl_l = re.search(r'<([\d\.]+)', line)
                match_g = re.search(r'\^([\d\.]+)', line)
                #```json[\s\S]*?```
                if match_g:
                    small_version = match_g.group(1)
                    big_version = None
                else:
                    if match_gl_g:
                        small_version = match_gl_g.group(1)
                    if match_gl_l:
                        big_version = match_gl_l.group(1)
        return small_version

    def read_contract(self,contract_path):
        with open(contract_path, errors="ignore") as f:
            contract = f.read()
        return contract

    def get_repos(self, contract):
        """
        # Read the contract to obtain the repository name (e.g., @0x/contracts-erc20)
        :param contract: Full contract string
        :return: Repo, e.g., @0x/contracts-erc20
        """
        lines = contract.split("\n")
        pattern_repo = r"(@[^/]+/[^/]+)"
        repos = set()
        for line in lines:
            if line[:6] == "import":
                lib_repo_match = re.findall(pattern_repo, line)
                if lib_repo_match:
                    repos.add(lib_repo_match[0])
        return list(repos)

    def read_changelog(self, changelog_path, keywords):
        """
        # Read the changelog and save the hierarchical structure in Markdown syntax
        :param changelog_path: Path to the changelog
        :param keyword: List of keywords to search for
        :return: A list of strings
        """
        # The number of lines to be saved.
        save_line_idxs = set()
        save_line_list = []

        # Current directory; MD level and number of rows
        md_titles = [None for i in range(6)]

        with open(changelog_path, errors="ignore") as f:
            changelog = f.read()
        changelog_lines = changelog.split("\n")
        for idx,line in enumerate(changelog_lines):
            if line.startswith('#'):
                heading_level = line.count('#', 0, len(line.split()[0])) - 1
                md_titles[heading_level] = idx
                for i in range(heading_level+1,6):
                    md_titles[i] = None
            if any(keyword.lower() in line.lower() for keyword in keywords):
                save_line_idxs.add(idx)
                for i in range(6):
                    if md_titles[i]:
                        save_line_idxs.add(md_titles[i])
        save_line_idxs_list = sorted(list(save_line_idxs))
        for idx in save_line_idxs_list:
            save_line_list.append(changelog_lines[idx])

        return "\n".join(save_line_list)

    def get_code(self, text):
        match = re.search(r"(?<=```)[\s\S]*?(?=```)", text)
        code = match.group(0)
        # Split into multiple rows
        lines = code.splitlines()
        # Delete the first line and recombine
        code = '\n'.join(lines[1:])
        return code

    def merge_repair_conract(self, origin_contract, repair_contract, error_locs):
        """
        Enter the original contract content, the repaired contract content, (starting position, ending position);
        Merge into a complete contract document
        """
        origin_lines = origin_contract.splitlines()
        repair_lines = repair_contract.splitlines()

        left_part = origin_lines[:error_locs[0]-1]
        right_part = origin_lines[error_locs[1]:]
        result = left_part + repair_lines + right_part
        return "\n".join(result)


    def run_sol(self, contract, solc_version):
        lines = contract.split("\n")
        text = contract

        with open("text.sol", mode="w") as f:
            f.write(text)
        os.system("solc-select use {}".format(solc_version))
        res = subprocess.Popen("solc {}".format("text.sol"), shell=True, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT)
        res_stdout = res.stdout.read().decode()
        res_stdout_lines = res_stdout.split("\n")

        res_flag = "Success"
        for line in res_stdout_lines:
            if "Warning" in line[:10]:
                res_flag = "Warning"
                break
        for line in res_stdout_lines:
            if "Error" in line[:10]:
                res_flag = "Error"
                break
        return res_flag, res_stdout

    def get_search_keywords(self, compile_error):
        """
        :param compile_error: enerate search keywords using LLM based on compilation error messages
        :return: Keyword List
        """
        prompt = prompt_template["get_search_keywords"].format(error_message=compile_error)
        response = self.get_response(prompt)
        res = json.loads(self.get_code(response))
        return res
    def get_error_line_idx(self, compile_error):
        error_list = compile_error.strip().split("\n\n")
        compile_error = error_list[0]
        retry_num = 0
        while retry_num<3:
            try:
                prompt = prompt_template["get_error_line_idx"].format(error_message=compile_error)
                response = self.get_response(prompt)
                res = int(response)
                retry_num=999
            except:
                retry_num+=1
                print("get_error_line_idx,retry num:{}".format(retry_num))
        return res

    def get_response(self, prompt):
        attempts = 5
        request_input = [{"role": "user", "content": prompt}]
        for attempt in range(attempts):
            try:
                # GPTAI
                response = requests.post(api_url, json={
                    'model': 'gpt-4o-mini',
                    'messages': request_input,
                    'max_tokens': 16000,
                }, headers={'Authorization': api_keys[0]})

                response_str = response.json()["choices"][0]["message"]["content"]
                self.input_num_tokens = self.get_num_tokens(prompt)
                self.output_num_tokens = self.get_num_tokens(response_str)
                self.sum_input_num_tokens += self.get_num_tokens(prompt)
                self.sum_output_num_tokens = +self.get_num_tokens(response_str)
                return response_str

            except Exception as e:
                print(f"请求失败: {e}. 尝试 {attempt + 1}/{attempts}...")
                time.sleep(20)

        return None

    def save_state(self):
        state = {
            "contract_path": self.contract_path,
            "init_contract": self.init_contract,
            "repair_flag": self.repair_flag,
            "input_num_tokens": self.input_num_tokens,
            "output_num_tokens": self.output_num_tokens,
            "contract_update_list": self.contract_update_list,
        }
        return state

    def get_num_tokens(self,text):
        """
        Retrieve the number of tokens for the string
        :param text: character string
        :return: Number of tokens, int
        """
        enc = tiktoken.encoding_for_model("gpt-4")
        token_ids = enc.encode(text)
        num_tokens = len(token_ids)
        return num_tokens

    def get_error_info(self, error_message):
        """
        Enter the complete error message, extract the error location and error information.
        Used for subsequent splicing into prompt
        :param error_message:
        :return: (4, "error:...")
        """
        error_list = error_message.strip().split("\n\n")
        res_list = []

        for part in error_list:
            if part[:5] == "Error":
                match = re.search(r'text\.sol:(\d+):', part)
                # This type of SPDX error does not report a line number, so when encountering this type of error, the beginning is extracted completely, so the line number 1 is directly returned
                if "Multiple SPDX license identifiers" in part:
                    error_message = '\n'.join(['// ' + line for line in part.split('\n')])
                    res_list.append((1, error_message))
                elif match:
                    error_message = '\n'.join(['// ' + line for line in part.split('\n')])
                    modified_string = '\n'.join(['// ' + line for line in part.split('\n')])
                    res_list.append((int(match.group(1)),error_message))
        return res_list

    def merge_contract_errors(self, contract, error_info):
        """
        Merge error information into the contract;
        """
        error_idx_set = set()
        contract_lines = contract.split("\n")
        error_point = 0
        for error_idx,error_message in error_info:
            if error_idx not in error_idx_set:
                error_idx_set.add(error_idx)
                contract_lines[error_idx-1] = "// <Error Start>\n"+contract_lines[error_idx-1]+"\n// <Error End>"

        return "\n".join(contract_lines)
    def merge_contract_errors_and_extract_first_error_contract(self, contract, compile_out):
        """
        Merge error information into the contract;
        """
        error_loc, error_contract_loc = self.extract_first_error_contract_loc_from_file(contract,
                                                                                         compile_out)
        error_info = self.get_error_info(compile_out)
        error_idx_set = set()
        contract_lines = contract.split("\n")
        error_point = 0
        for error_idx,error_message in error_info:
            if error_idx not in error_idx_set:
                error_idx_set.add(error_idx)
                contract_lines[error_idx-1] = "// <Error Start>\n"+contract_lines[error_idx-1]+"\n// <Error End>"

        return "\n".join(contract_lines[error_contract_loc[0]-1:error_contract_loc[1]])

    def get_contract_loc_from_contract(self, contract):
        """
        Input the contract file to obtain the starting and ending positions of each contract/library/interface in the file
        """
        ast = parseString(contract)
        loc_list = []
        for _contract in ast["subcontracts"]:
            start_loc = int(_contract["loc"]["start"].split(":")[0])
            end_loc = int(_contract["loc"]["end"].split(":")[0])
            loc_list.append((start_loc,end_loc))
        return loc_list

    def extract_first_error_contract_loc_from_file(self, contract, error_info):
        """
        Extract the contract with the error location from the contract file
        :param contract: Contract file string
        :param error_info: Compile error message
        :return: (Error location, (Error starting point of contract, Error ending point of contract)
        """

        def find_range(num, ranges):
            min_num = 99999
            for r in ranges:
                if r[0] <= min_num:
                    min_num = r[0]
                if r[0] <= num <= r[1]:  # Check if num is within the interval r
                    return r
            return (1,min_num-1)  # If no suitable interval is found, return the position from 0 to the beginning of the first contract

        error_idx_set = set()
        contract_lines = contract.split("\n")
        error_point = 0
        error_info = self.get_error_info(error_info)
        loc_list = self.get_contract_loc_from_contract(contract)

        for error_idx,error_message in error_info:
            if error_idx not in error_idx_set:
                error_idx_set.add(error_idx)
                error_contract_loc = find_range(error_idx,loc_list)
                return (error_idx,error_contract_loc)

    def repair_contract(self, compile_version, repair_mode, extract_context=False, retry_num = 10):
        """
        Read the contract string from the agent object and repair the contract. And save the repair diary.

        :param compile_version:  Compiled version
        :param repair_mode:  Repair mode, contract，compile，compile_changelog
        :param extract_context:  Whether to extract the contract, True is to extract, False is to input the complete contract file
        :param retry_num:  retry count
        :return:  Dictionary, for repairing historical information
        """
        compile_flag, compile_out = self.run_sol(self.now_contract, compile_version)

        if compile_flag == "Error":
            if len(self.contract_update_list) >= retry_num:
                now_state = {
                    "contract": self.now_contract,
                    "compile_result": compile_out,
                    "error_line": "",
                    "update_function": repair_mode,  # C=compile, CR=compile+RAG, N=Nothing
                    "prompt": "",
                    "LLM_respone": "",
                    "input_num_tokens": self.input_num_tokens,
                    "output_num_tokens": self.output_num_tokens,
                    "timestamp":self.start_timestamp - time.time()}
                self.contract_update_list.append(now_state)
                return self.save_state()
            if repair_mode == "contract":
                prompt = prompt_template["repair_by_contract"].format(smart_contract=self.now_contract)
            elif repair_mode == "compile":
                if extract_context==False:
                    contract_tmp = self.merge_contract_errors(self.now_contract, self.get_error_info(compile_out))
                else:
                    error_loc, error_contract_loc = self.extract_first_error_contract_loc_from_file(self.now_contract,
                                                                                                     compile_out)
                    contract_tmp = self.merge_contract_errors_and_extract_first_error_contract(self.now_contract, compile_out)
                    pass
                prompt = prompt_template["repair_by_compile"].format(smart_contract=contract_tmp, error_message=compile_out)
            elif repair_mode == "compile_changelog":
                try:
                    search_keywords = self.get_search_keywords(compile_out)
                    repo_path = self.get_repos(self.now_contract)
                    # repo_path = "solidity"
                    changelog_info = ""
                    for repo_path in self.get_repos(self.now_contract):
                        try:
                            changelog_info_tmp = self.read_changelog(os.path.join(repo_path,"CHANGELOG.md"),search_keywords)
                            changelog_info += "search keys:{}\n {} changelog:{}\n".format(search_keywords,repo_path,changelog_info_tmp)
                        except Exception as e:
                            print("No existed {} changelog file!".format(repo_path))
                    if extract_context == False:
                        contract_tmp = self.merge_contract_errors(self.now_contract,self.get_error_info(compile_out))
                        prompt = prompt_template["repair_by_compile_changelog_input_file"].format(smart_contract=contract_tmp,
                                                                                       error_message=compile_out,
                                                                                       changelog_information=changelog_info)
                    else:
                        error_loc, error_contract_loc = self.extract_first_error_contract_loc_from_file(
                            self.now_contract,
                            compile_out)
                        contract_tmp = self.merge_contract_errors_and_extract_first_error_contract(self.now_contract,
                                                                                                   compile_out)
                        prompt = prompt_template["repair_by_compile_changelog"].format(smart_contract=contract_tmp, error_message = compile_out, changelog_information = changelog_info)
                except Exception as e:
                    print("Fail!")
                    now_state = {
                        "contract": self.now_contract,
                        "compile_result": compile_out,
                        "error_line": "",
                        "update_function": repair_mode,  # C=compile, CR=compile+RAG, N=Nothing
                        "prompt": "Fail! Reason：{}".format(e),
                        "LLM_respone": "",
                        "input_num_tokens": self.input_num_tokens,
                        "output_num_tokens": self.output_num_tokens,
                        "timestamp":self.start_timestamp - time.time()}
                    self.contract_update_list.append(now_state)
                    return self.save_state()
            elif repair_mode == "compile_changelog_mix":
                if len(self.contract_update_list) < 1:
                    prompt = prompt_template["repair_by_compile"].format(smart_contract=self.now_contract, error_message=compile_out)
                else:
                    try:
                        search_keywords = self.get_search_keywords(compile_out)
                        repo_path = self.get_repos(self.now_contract)[0]
                        changelog_info = self.read_changelog(os.path.join(repo_path, "CHANGELOG.md"), search_keywords)
                        prompt = prompt_template["repair_by_compile_changelog"].format(smart_contract=self.now_contract,
                                                                                       error_message=compile_out,
                                                                                       changelog_information=changelog_info)
                    except Exception as e:
                        print("Fail!")
                        now_state = {
                            "contract": self.now_contract,
                            "compile_result": compile_out,
                            "error_line": "",
                            "update_function": repair_mode,  # C=compile, CR=compile+RAG, N=Nothing
                            "prompt": "Fail! Reason：{}".format(e),
                            "LLM_respone": "",
                            "input_num_tokens": self.input_num_tokens,
                            "output_num_tokens": self.output_num_tokens,
                            "timestamp":self.start_timestamp - time.time()}
                        self.contract_update_list.append(now_state)
                        return self.save_state()
            else:
                print("Fail!")
                return False

            response = self.get_response(prompt)
            now_state = {
                "contract": self.now_contract,
                "compile_result": compile_out,
                "error_line": "",
                "update_function": repair_mode,  # C=compile, CR=compile+RAG, N=Nothing
                "prompt": prompt,
                "LLM_respone": response,
                "input_num_tokens": self.input_num_tokens,
                "output_num_tokens": self.output_num_tokens,
                "timestamp":self.start_timestamp - time.time()}
            try:
                if extract_context==False:
                    self.now_contract = self.get_code(response.split("# The complete contract after repair")[-1])
                else:
                    repair_contract_part = self.get_code(response.split("# The complete contract after repair")[-1])
                    self.now_contract = self.merge_repair_conract(self.now_contract, repair_contract_part,
                                                                  error_contract_loc)
                self.contract_update_list.append(now_state)
                return self.repair_contract(compile_version = compile_version, repair_mode = repair_mode, retry_num = retry_num,extract_context = extract_context)
            except:
                self.contract_update_list.append(now_state)
                return self.save_state()

        else:
            self.repair_flag = True
            now_state = {
                "contract": self.now_contract,
                "compile_result": compile_out,
                "error_line": "",
                "update_function": repair_mode,  # C=compile, CR=compile+RAG, N=Nothing
                "prompt": "",
                "LLM_respone": "",
                "input_num_tokens": self.input_num_tokens,
                "output_num_tokens": self.output_num_tokens,
                "timestamp":self.start_timestamp - time.time()}
            self.contract_update_list.append(now_state)
            return self.save_state()