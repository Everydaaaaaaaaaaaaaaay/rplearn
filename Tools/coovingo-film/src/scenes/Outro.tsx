import {
  CanvasImage,
  Interactive,
  interpolate,
  useCurrentFrame,
} from "remotion";
import { Paper, media, clamp, ease } from "../design";
export const Outro = () => {
  const frame = useCurrentFrame();
  return (
    <Paper tone="#eaf1ef">
      <Interactive.Div
        name="Brand icon"
        style={{
          position: "absolute",
          left: 394,
          top: 206,
          width: 292,
          height: 292,
          borderRadius: 66,
          overflow: "hidden",
          boxShadow: "0 28px 65px #23465724",
          opacity: interpolate(frame, [15, 48], [0, 1], clamp),
          scale: interpolate(frame, [15, 86], [0.88, 1], {
            ...clamp,
            easing: ease,
          }),
        }}
      >
        <CanvasImage src={media("icon.png")} style={{ width: "100%" }} />
      </Interactive.Div>
      <Interactive.Div
        name="Brand and promise"
        style={{
          position: "absolute",
          left: 60,
          right: 60,
          top: 557,
          textAlign: "center",
          translate: interpolate(frame, [30, 90], ["0px 40px", "0px 0px"], {
            ...clamp,
            easing: ease,
          }),
          opacity: interpolate(frame, [30, 60], [0, 1], clamp),
        }}
      >
        <div style={{ fontSize: 38, letterSpacing: 4 }}>
          咕游记{" "}
          <span style={{ color: "#6b7f88", fontSize: 30, letterSpacing: 2 }}>
            COOVINGO
          </span>
        </div>
        <div
          style={{
            fontSize: 102,
            fontWeight: 600,
            letterSpacing: -4,
            lineHeight: 1.28,
            marginTop: 45,
          }}
        >
          把英语，
          <br />
          聊成生活。
        </div>
        <div style={{ fontSize: 44, color: "#58727b", marginTop: 28 }}>
          从一句 Hello，开始你的旅程。
        </div>
      </Interactive.Div>
      <div
        style={{
          position: "absolute",
          left: -120,
          right: -120,
          top: 1130,
          height: 475,
          overflow: "hidden",
          maskImage:
            "linear-gradient(transparent,black 6%,black 77%,transparent)",
        }}
      >
        {[
          "01-messages.png",
          "08-story.png",
          "03-dictionary.png",
          "09-favorites.png",
        ].map((file, i) => (
          <div
            key={file}
            style={{
              position: "absolute",
              left: i * 326 + interpolate(frame, [0, 384], [0, -65], clamp),
              top: i % 2 ? 50 : 0,
              width: 296,
              height: 640,
              borderRadius: 28,
              overflow: "hidden",
              rotate: `${i % 2 ? 4 : -4}deg`,
              boxShadow: "0 15px 35px #1b394520",
            }}
          >
            <CanvasImage src={media(file)} style={{ width: "100%" }} />
          </div>
        ))}
      </div>
      <div
        style={{
          position: "absolute",
          left: 74,
          right: 74,
          top: 1683,
          textAlign: "center",
          fontSize: 25,
          lineHeight: 1.5,
          color: "#536b76",
        }}
      >
        <div style={{ marginBottom: 15 }}>
          AI 虚构旅伴 · 实机与模拟器演示画面
        </div>
        <div>Music: “George Street Shuffle” — Kevin MacLeod</div>
        <div>incompetech.com · CC BY 4.0 · Edited excerpt</div>
        <div>creativecommons.org/licenses/by/4.0/</div>
      </div>
    </Paper>
  );
};
