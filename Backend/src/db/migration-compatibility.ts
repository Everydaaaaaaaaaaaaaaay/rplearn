/**
 * 只允许已逐项确认可向后兼容的后续迁移；不能泛化为“数量更多就兼容”。
 * 0041 新增学习偏好表；0042 增加可空退役时间并放宽未完成练习唯一索引。
 * 0042 不改变旧答案、积分或完成时间；回退程序仍能读取原练习。
 * 0043 仅新增可空的学习目标数组，旧程序继续读取原单目标列。
 * 必须先发布此兼容版本，再执行该迁移，才能安全回退程序而保留数据。
 */
const compatibleAdditions = new Map([
  // 0047/0048 add isolated shared-chat tables and indexes. Deploy this compatibility
  // checkpoint before applying them so a program rollback can preserve accepted data.
  [1793836800000, "8fa60a7cf09d8987f325f41d936ce20fa008012e98c62d55a5137045b9ed15e1"],
  [1793836801000, "2126908f51849a242148207ef2dd8df540e9df41740814fb4e4fc9e7c7fa6e69"],
  // 0046 adds appointment-owned tables/routes without changing existing content or relationship columns.
  [1793490000000, "cd5fe7464ffcf6ea5c769308db938e8f86b248ff354fc83e906b3de3cf10a1bd"],
  [1793410000000, "754294e982590017a100d35349923686b0d0efc066d61601b86c421062fe570e"],
  [1793404800000, "d56a9fd8af5dc82954169765edf96556346eda00871f94ffb2f242616728c389"],
  [1793318400000, "c67cd02ad3db4eb5d84e21176a2c3066daf080bf00e122db2af346c30fd26743"],
  [1792713600000, "abe601bf211103949624799adf146eb5df39f80479760c8956b86ef2c4ee8657"],
  [1791676800000, "34e472719cee3febb55ff7b3e8bac92c0cecf48d7b62649c9628761dc0b1032e"],
]);

export function assertCompatibleMigrationInventory(
  expected: number,
  applied: readonly { hash: string; created_at: string | number }[],
): void {
  const ordered = [...applied].sort(
    (a, b) => Number(a.created_at) - Number(b.created_at),
  );
  if (
    ordered.length < expected ||
    new Set(ordered.map((row) => Number(row.created_at))).size !== ordered.length ||
    ordered
      .slice(expected)
      .some((row) => compatibleAdditions.get(Number(row.created_at)) !== row.hash)
  )
    throw new Error("数据库迁移与当前程序不兼容。");
}
