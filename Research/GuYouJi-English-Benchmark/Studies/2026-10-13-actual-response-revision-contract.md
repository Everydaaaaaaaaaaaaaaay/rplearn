# 实际作答与修订记录缺口补充

此前研究AttemptTrace0.1只有response_status，不能用它复算用户选项、填空或标注，也不能从末次状态恢复首次作答。补充0.2Schema及独立原创样例，具体范围见[说明](../Attempts/Response-v0.2.md)。没有修改后端、数据库或iOS，也没有收集真实用户资料。

0.2记录绑定已冻结题目版本，选择项身份、完整空位身份和标注文字块坐标可检查；逐题revision记录立即前一事件，明确跳过后恢复。四份原创fixture覆盖选择/跳过、Unicode原始文本、写作及填空与标注复合任务的修订。32项格式/身份/修订失败被拒绝，原0.1的三份fixture和33项检查通过。

工具保留原始内容，并允许结构正确但语言上答错或超限的响应，不把录入有效等同得分。报告只列事件身份，没有复制实际文字/标注；这项本机行为不等于生产数据隐私审计。不存在真实作答、防篡改记录、评分效果或有效学习用时证据，阶段与必需缺口不关闭。

复算使用缓存固定jsonschema依赖和bundled Python运行`Tools/check_attempt_response_contract.py`、`Tools/check_attempt_trace_contract.py`。审计输出留在ignored研究缓存，Registry保存大小、SHA及研究用途边界；Git仅含原创方法和结构示例。
