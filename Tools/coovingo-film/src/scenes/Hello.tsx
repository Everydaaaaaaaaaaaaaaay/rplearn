import {
  CanvasImage,
  Interactive,
  interpolate,
  useCurrentFrame,
} from "remotion";
import {
  Paper,
  Eyebrow,
  Title,
  Note,
  Foot,
  Screen,
  clamp,
  ease,
  media,
} from "../design";
export const Hello = () => {
  const frame = useCurrentFrame();
  return (
    <Paper tone="#edf4f2">
      <Eyebrow>咕游记 · 和世界聊聊</Eyebrow>
      <Title>
        有些朋友，
        <br />
        让你想多聊一句。
      </Title>
      <Note>用英语，分享生活里的小事。</Note>
      <Interactive.Div
        name="Warm sun"
        style={{
          position: "absolute",
          left: 680,
          top: 620,
          width: 520,
          height: 520,
          borderRadius: "50%",
          background: "#ecd6a8",
          scale: interpolate(frame, [20, 150], [0.75, 1], {
            ...clamp,
            easing: ease,
          }),
        }}
      />
      <Screen file="01-messages.png" x={196} y={563} w={670} angle={-3} />
      <Interactive.Div
        name="Ruby portrait"
        style={{
          position: "absolute",
          left: 65,
          top: 1290,
          width: 164,
          height: 164,
          borderRadius: "50%",
          overflow: "hidden",
          boxShadow: "0 15px 35px #263c4720",
          translate: interpolate(frame, [95, 170], ["-70px 90px", "0px 0px"], {
            ...clamp,
            easing: ease,
          }),
          opacity: interpolate(frame, [95, 125], [0, 1], clamp),
        }}
      >
        <CanvasImage src={media("ruby.png")} style={{ width: 164 }} />
      </Interactive.Div>
      <Foot>AI 旅伴 · iPhone 实机界面</Foot>
    </Paper>
  );
};
