import { Paper, Headline, NativeScreen } from "../design";
export const Presence = () => (
  <Paper background="bg-london.jpg" dark>
    <Headline>在交流中，练习英语</Headline>
    <NativeScreen file="chat-motion.mp4" video x={195} y={315} width={690} />
  </Paper>
);
