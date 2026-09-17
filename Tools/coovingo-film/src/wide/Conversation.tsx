import { Canvas, Copy, Phone, DetailLine } from "./design";
import { CanvasImage, interpolate, useCurrentFrame } from "remotion";
import { clamp, ease, media } from "../design";
export const Conversation = () => {
  const f = useCurrentFrame();
  return (
    <Canvas dark bg="bg-london.jpg">
      {f < 275 && (
        <>
          <Copy
            title={"想说的日常，\n就是练习的内容。"}
            body={
              "和不同性格的 AI 角色聊兴趣、聊近况。\n在有来有回的交流里，练习英语表达。"
            }
            top={200}
            exitAt={245}
          />
          <DetailLine
            dark
            items={[
              "有各自的经历与兴趣",
              "按当地作息联系",
              "自然打字、分条回复",
            ]}
            top={810}
            exitAt={245}
          />
        </>
      )}
      {/* Keep the native image mounted; animate its own alpha instead of a parent
    around Interactive children. This avoids first-frame compositing flashes. */}
      <CanvasImage
        src={media("04-companion.png")}
        style={{
          position: "absolute",
          left: 120,
          top: 120,
          width: 380,
          border: "5px solid #d6dcd7",
          borderRadius: 34,
          boxShadow: "0 30px 65px #08252d45",
          opacity: interpolate(f, [275, 311], [0, 1], clamp),
          translate: interpolate(f, [275, 341], ["0px 25px", "0px 0px"], {
            ...clamp,
            easing: ease,
          }),
          rotate: "-2deg",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 580,
          top: 260,
          width: 570,
          opacity: interpolate(f, [281, 317], [0, 1], clamp),
          translate: interpolate(f, [281, 341], ["0px 15px", "0px 0px"], {
            ...clamp,
            easing: ease,
          }),
        }}
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
      <Phone file="chat-motion.mp4" video x={1300} y={80} w={420} />
    </Canvas>
  );
};
