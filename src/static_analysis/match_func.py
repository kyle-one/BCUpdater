import os
import re
import sys
import json
# 获取当前文件的目录
current_dir = os.path.dirname(os.path.abspath(__file__))
# 添加 f1 目录到搜索路径
sys.path.append(os.path.join(current_dir, 'static_analysis'))
from SolidityParser import parseFile

def get_subfolder_names(directory):
    """
    遍历给定文件夹的深度为1的子文件夹，将子文件夹名称保存到列表中。
    """
    subfolders = []
    for entry in os.scandir(directory):
        if entry.is_dir():  # 判断是否是子文件夹
            subfolders.append(entry.name)
    return subfolders
def find_sol_files(directory):
    """
    查找某个路径下的所有sol文件
    """
    sol_files = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith(".sol") and not file.startswith("."):
                sol_files.append(os.path.join(root, file))
    return sol_files

def extract_after_node_modules(path):
    """
    提取路径中 'node_modules/' 后的字符串。
    """
    match = re.search(r'node_modules/(.*)', path)
    return match.group(1) if match else None
def extract_path(file_path):
    """
    匹配某个绝对路径下的路径
    :param file_path:
    :return:
    """
    match = re.match(r"(.*\/)", file_path)
    if match:
        return match.group(1)
    return None


lib_list = ["/Volumes/JZAO/lib/@openzeppelin/contracts",
            "/Volumes/JZAO/lib/@openzeppelin/contracts-upgradeable",
            "/Volumes/JZAO/lib/@openzeppelin/contracts-ethereum-package",
            "/Volumes/JZAO/lib/@chainlink/contracts",
            "/Volumes/JZAO/lib/@balancer-labs/v2-pool-utils",
            "/Volumes/JZAO/lib/@balancer-labs/v2-solidity-utils"]

# 根据lib list获取对应的各个版本号
lib_viersion_dict = {i:[] for i in lib_list}
for lib in lib_viersion_dict:
    version_list = get_subfolder_names(lib)
    version_list = sorted(version_list, reverse=True)
    lib_viersion_dict[lib] = version_list

# 根据各个版本号获取对应的文件
lib_file_dict = {i:[] for i in lib_list}
for lib in lib_viersion_dict:
    for version in lib_viersion_dict[lib]:
        sol_files = find_sol_files(os.path.join(lib,version))
        lib_file_dict[lib].extend(sol_files)

# 测试extract_after_node_modules函数
# for lib in lib_file_dict:
#     for file in lib_file_dict[lib]:
#         print(extract_after_node_modules(file))
#     break


# 主流程：
# 对所有的sol文件先做预处理：将所有的sol文件转化为静态分析AST语法树，保存为同路径下同名称的json文件
for lib in lib_file_dict:
    for file in lib_file_dict[lib]:
        print(file)
        # print(file+".json")
        ast = parseFile(file)
        print(ast)
        with open(file+".json","w") as f:
            json.dump(ast,f)