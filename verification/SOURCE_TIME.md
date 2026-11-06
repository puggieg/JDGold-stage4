# 来源时间解析依据

阶段三在 2026-10-14 用 curl 请求了现有端点，未修改 URL、参数、SKU 或请求头。响应保存在 fixtures/，这里只记录公开行情，不包含 Bark Key。

## 新浪

```bash
curl -H 'Referer: https://finance.sina.com.cn' 'https://hq.sinajs.cn/list=hf_XAU,hf_GC'
```

GB18030 原始响应保存在 `fixtures/sina.gb18030`，UTF-8 内容如下：

```text
var hq_str_hf_XAU="4098.19,4161.000,4098.19,4098.54,4170.25,4079.56,22:37:00,4161.00,4161.97,0,0,0,2026-10-14,伦敦金（现货黄金）";
var hq_str_hf_GC="4119.908,,4121.200,4121.500,4193.500,4101.600,22:38:32,4177.300,4184.200,0,3,1,2026-10-14,纽约黄金,0";
```

原始逗号数组：parts[0] 当前价、parts[6] 时间、parts[7] 昨收、parts[8] 今开、parts[12] 日期。
GC 的 parts[1] 为空，不能用作昨收。日期/时间按 Asia/Shanghai 合并，验证不允许非法日期自动滚动。
阶段二的昨收核对注释原样保留，阶段三另附本次真实响应作为时间字段依据。

## 银行

```bash
curl 'https://api.jdjygold.com/gw/generic/hj/h5/m/latestPrice'
curl -H 'Content-Type: application/json' -d '{"reqData":{"productSku":"2005453243"}}' 'https://api.jdjygold.com/gw2/generic/jrm/h5/m/icbcLatestPrice?productSku=2005453243'
curl -H 'Content-Type: application/json' -d '{"reqData":{"productSku":"1961543816"}}' 'https://api.jdjygold.com/gw2/generic/jrm/h5/m/stdLatestPrice?productSku=1961543816'
```

实际 datas 子对象如下，完整响应见 fixtures/：

### minsheng

```json
{
  "upAndDownRate": "-1.35%",
  "productSku": "21001001000001",
  "demode": false,
  "priceNum": "B092C0EC09048DFC7ECB4D2E729252EF",
  "price": "885.04",
  "yesterdayPrice": "897.15",
  "upAndDownAmt": "-12.11",
  "time": "1791988717000",
  "id": 42819462
}
```

`time / 1000` 转为北京时间：2026-10-14T22:38:37+08:00，再乘回 1000 与原值一致。

### icbc

```json
{
  "upAndDownRate": "-1.58%",
  "productSku": "2005453243",
  "demode": true,
  "priceNum": "ICBCGOLD_20261014223000015000",
  "price": "884.62",
  "yesterdayPrice": "898.86",
  "upAndDownAmt": "-14.24",
  "time": "1791988200000",
  "id": 9908399
}
```

`time / 1000` 转为北京时间：2026-10-14T22:30:00+08:00，再乘回 1000 与原值一致。

### zheshang

```json
{
  "upAndDownRate": "-1.33%",
  "productSku": "1961543816",
  "demode": false,
  "priceNum": "8d5cd097-8e4f-4fb8-a12f-e84d813d45a9",
  "price": "885.46",
  "yesterdayPrice": "897.42",
  "upAndDownAmt": "-11.96",
  "id": 42819556,
  "time": "1791988730000"
}
```

`time / 1000` 转为北京时间：2026-10-14T22:38:50+08:00，再乘回 1000 与原值一致。

## 美元指数

```bash
curl -H 'User-Agent: Mozilla/5.0' 'https://push2.eastmoney.com/api/qt/stock/get?secid=100.UDI&fields=f43,f57,f58,f60,f169,f170'
```

本次响应体为空，已保存在 `fixtures/eastmoney.txt`；现有参数未包含时间字段。不得据此伪造来源时间，也不添加 f124 或其他字段。
显示“来源时间未提供”；请求失败仍保留缓存、变灰并标延迟。持续未变价满五分钟也标“休市/延迟”。

## 时间用途

sourceUpdatedAt：来源发布时刻；lastSuccessAt：最后一次有效抓取，用于缓存诊断；lastPriceChangeAt：当前 App 观察到价格最后变化的时刻。
只在报价有效且价格改变时更新最后变化时间。未知來源时间不会自动等同请求失败，不会用抓取时间替代它。
“休市/延迟”只表达数据时效，不保证已识别市场交易日历。

参考平台能力说明：
- Apple SMAppService（macOS 13+）：https://developer.apple.com/documentation/servicemanagement/smappservice
- Apple 通知授权：https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:)
- Bark 官方项目与客户端文档：https://github.com/Finb/Bark
- Bark 手机应用说明：https://apps.apple.com/cn/app/id1403753865
