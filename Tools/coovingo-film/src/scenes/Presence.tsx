import { Video } from "@remotion/media";
import { Interactive, interpolate, useCurrentFrame } from "remotion";
import {
  Paper,
  Eyebrow,
  Title,
  Note,
  Foot,
  Detail,
  media,
  clamp,
  ease,
} from "../design";
export const Presence = () => {
  const frame = useCurrentFrame();
  return (
    <Paper tone="#f4f0e8">
      <Eyebrow>01 / 每个人，都不一样</Eyebrow>
      <Title size={88}>
        有自己的生活，
        <br />
        也有自己的节奏。
      </Title>
      <Note>当地作息 · 鲜明个性 · 自然分条回复</Note>
      <Interactive.Div
        name="Personality introduction"
        style={{
          opacity: interpolate(frame, [155, 193], [1, 0], clamp),
          translate: interpolate(frame, [155, 193], ["0px 0px", "-70px 0px"], {
            ...clamp,
            easing: ease,
          }),
        }}
      >
        <Detail
          file="04-companion.png"
          top={610}
          height={665}
          crop={325}
          delay={35}
        />
        <div
          style={{
            position: "absolute",
            left: 88,
            top: 1420,
            fontSize: 50,
            lineHeight: 1.5,
          }}
        >
          咖啡师、海洋生物学在读。
          <br />
          <span style={{ color: "#6d7d82" }}>周末，也是冲浪教练。</span>
        </div>
      </Interactive.Div>
      <Interactive.Div
        name="Native reply recording"
        style={{
          opacity: interpolate(frame, [155, 193], [0, 1], clamp),
          translate: interpolate(frame, [155, 215], ["70px 0px", "0px 0px"], {
            ...clamp,
            easing: ease,
          }),
        }}
      >
        <div
          style={{
            position: "absolute",
            left: 86,
            top: 590,
            width: 908,
            height: 136,
            borderRadius: 32,
            overflow: "hidden",
            background: "#f5f7f7",
            boxShadow: "0 12px 40px #173d4812",
          }}
        >
          <Video
            from={150}
            src={media("chat-motion.mp4")}
            trimBefore={360}
            muted
            style={{ position: "absolute", width: 908, top: -130 }}
          />
        </div>
        <div
          style={{
            position: "absolute",
            left: 86,
            top: 760,
            width: 908,
            height: 914,
            borderRadius: 38,
            overflow: "hidden",
            background: "#f5f7f7",
            boxShadow: "0 24px 70px #173d4824",
          }}
        >
          <Video
            from={150}
            src={media("chat-motion.mp4")}
            trimBefore={360}
            muted
            style={{ position: "absolute", width: 908, top: -1070 }}
          />
        </div>
      </Interactive.Div>
      <Foot>忙时稍等，开聊有来有回。</Foot>
    </Paper>
  );
};
