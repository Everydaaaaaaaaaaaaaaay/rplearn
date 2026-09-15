import { Paper, Eyebrow, Title, Note, Foot, Detail } from "../design";
export const Words = () => (
  <Paper tone="#eef4f2">
    <Eyebrow>04 / 好奇，不必打断</Eyebrow>
    <Title>
      不懂的词，
      <br />
      不用离开对话。
    </Title>
    <Note>顺着语境，读懂那句话。</Note>
    <Detail file="03-dictionary.png" top={570} height={1130} crop={350} />
    <Foot>释义 · 双语例句 · 发音 · 收藏</Foot>
  </Paper>
);
