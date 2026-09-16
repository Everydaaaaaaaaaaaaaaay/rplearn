import { Canvas, Copy, Phone, DetailLine } from "./design";
import { interpolate, useCurrentFrame } from "remotion";
import { clamp } from "../design";
export const Conversation = () => {
  const f = useCurrentFrame();
  return (
    <Canvas dark bg="bg-london.jpg">
      {f < 275 && (
        <div style={{ opacity: interpolate(f, [245, 275], [1, 0], clamp) }}>
          <Copy
            title={"想说的日常，\n就是练习的内容。"}
            body={
              "和不同性格的 AI 角色聊兴趣、聊近况。\n在有来有回的交流里，练习英语表达。"
            }
            top={200}
          />
          <DetailLine
            dark
            items={[
              "有各自的经历与兴趣",
              "按当地作息联系",
              "自然打字、分条回复",
            ]}
            top={810}
          />
        </div>
      )}
      {f >= 275 && (
        <div style={{ opacity: interpolate(f, [275, 305], [0, 1], clamp) }}>
          <Phone file="04-companion.png" x={120} y={120} w={380} angle={-2} />
          <div
            style={{ position: "absolute", left: 580, top: 260, width: 570 }}
          >
            <div style={{ fontSize: 65, lineHeight: 1.35 }}>
              不同的经历，
              <br />
              不同的话题。
            </div>
            <div
              style={{
                fontSize: 31,
                lineHeight: 1.85,
                opacity: 0.8,
                marginTop: 40,
              }}
            >
              咖啡、海洋、冲浪……
              <br />
              每个角色都有自己的兴趣与背景。
              <br />
              按当地作息，以自然节奏回应。
            </div>
          </div>
        </div>
      )}
      <Phone file="chat-motion.mp4" video x={1300} y={80} w={420} />
    </Canvas>
  );
};
