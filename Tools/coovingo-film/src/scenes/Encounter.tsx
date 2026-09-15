import { Paper, Eyebrow, Title, Note, Foot, Screen } from "../design";
export const Encounter = () => (
  <Paper tone="#e9eff0">
    <Eyebrow>02 / 让相遇发生</Eyebrow>
    <Title>
      走进一座城，
      <br />
      遇见不同的人。
    </Title>
    <Note>15 座城市，把英语带进沿途的日常。</Note>
    <Screen
      file="city-singapore.png"
      x={30}
      y={615}
      w={545}
      angle={-5}
      delay={35}
    />
    <Screen
      file="07-encounter.png"
      x={452}
      y={772}
      w={552}
      angle={5}
      delay={65}
    />
    <Foot>城市探索 · 原创人物邂逅</Foot>
  </Paper>
);
