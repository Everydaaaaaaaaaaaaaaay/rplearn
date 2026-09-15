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
    <Paper background="bg-bookshop.jpg" dark>
      <Interactive.Div
        name="Coovingo English learning"
        style={{
          position: "absolute",
          top: 480,
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
            color: "#dacdb1",
            marginTop: 16,
          }}
        >
          COOVINGO
        </div>
        <div style={{ fontSize: 72, fontWeight: 400, marginTop: 74 }}>
          边聊边学，没压力
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
          color: "#d5d6cc",
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
