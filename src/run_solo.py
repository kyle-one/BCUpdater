
import json
import pandas as pd
from agent import ContractAgent
import os

file_path = "../dataset/no_lib/0b76544f6c413a555f309bf76260d1e02377c02a_INT.sol"

agent = ContractAgent(file_path)
agent.replace_version(agent.init_contract, "0.8.28")

# repair_mode = "contract" or "compile" or "compile_changelog"
res = agent.repair_contract(compile_version="0.8.28", repair_mode="compile", extract_context=False,
                            retry_num=5)

print(res["repair_flag"])
with open("run_solo_res.jsonl", "a") as f:
    # json.dump(res,f)
    f.write(json.dumps(res) + '\n')
