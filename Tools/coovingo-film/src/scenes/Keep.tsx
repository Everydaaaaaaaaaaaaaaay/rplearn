import { Paper, Eyebrow, Title, Note, Foot, Detail } from "../design";
export const Keep = () => (
  <Paper tone="#f4eee3">
    <Eyebrow>05 / 把喜欢的表达，留下来</Eyebrow>
    <Title>
      聊过的，
      <br />
      慢慢变成你的。
    </Title>
    <Note>从一个单词，到一句想再用的表达。</Note>
    <Detail file="09-favorites.png" top={580} height={1190} crop={480} />
    <Foot>单词、语法与句子，整理在一起。</Foot>
  </Paper>
);
