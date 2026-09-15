import {
  CanvasImage,
  Interactive,
  interpolate,
  useCurrentFrame,
} from "remotion";
import { Paper, media, clamp, ease } from "../design";
export const Outro = () => {
  const f = useCurrentFrame();
  return (
    <Paper>
      <Interactive.Div
        name="Coovingo English learning"
        style={{
          position: "absolute",
          top: 560,
          left: 80,
          right: 80,
          textAlign: "center",
          opacity: interpolate(f, [8, 45], [0, 1], clamp),
          transform: `translateY(${interpolate(f, [0, 75], [26, 0], { ...clamp, easing: ease })}px)`,
        }}
      >
        <CanvasImage
          src={media("icon.png")}
          style={{ width: 180, height: 180, borderRadius: 40 }}
        />
        <div
          style={{
            fontSize: 80,
            fontWeight: 500,
            marginTop: 42,
            letterSpacing: 4,
          }}
        >
          咕游记
        </div>
        <div
          style={{
            fontSize: 26,
            letterSpacing: 7,
            color: "#6a8595",
            marginTop: 16,
          }}
        >
          COOVINGO
        </div>
        <div style={{ fontSize: 52, fontWeight: 400, marginTop: 74 }}>
          让英语学习，有情境。
        </div>
      </Interactive.Div>
      <div
        style={{
          position: "absolute",
          bottom: 110,
          left: 70,
          right: 70,
          textAlign: "center",
          fontSize: 20,
          lineHeight: 1.65,
          color: "#72818b",
        }}
      >
        <div>产品演示画面 · AI 虚构角色</div>
        <div>Music: George Street Shuffle — Kevin MacLeod</div>
        <div>incompetech.com · CC BY 4.0 · Edited excerpt</div>
        <div>creativecommons.org/licenses/by/4.0/</div>
      </div>
    </Paper>
  );
};
