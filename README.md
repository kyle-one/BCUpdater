# BCUpdater
Open-source implementation of the BCUpdater paper's tool, verification contract dataset, and user study data.

## Directory Structure
- src
  - @openzeppelin: Please download the latest OpenZeppelin library in this folder.
  - agent.py :Implementation of the BCUpdater tool.
  - run_solo.py: Script for running the BCUpdater tool.
- dataset: Evaluation dataset from the paper.
- User Study: User study data.

## How to Use
```python
pip install -r requirements.txt
solc-select install 0.8.28
python3 run_solo.py
```