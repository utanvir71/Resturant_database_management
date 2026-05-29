from pathlib import Path
import argparse

from pyspark.sql import SparkSession
from pyspark.sql.functions import avg, count, desc, sum as spark_sum


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE_DIR = PROJECT_ROOT / "exports"
OUTPUT_DIR = PROJECT_ROOT / "exports" / "spark_summaries"


def create_spark_session():
    return (
        SparkSession.builder
        .appName("RestaurantBigDataAnalytics")
        .getOrCreate()
    )


def read_csv_if_exists(spark, source_dir, filename):
    path = source_dir / filename
    if not path.exists():
        print(f"Missing {path.name}; skipping related Spark summary.")
        return None

    return (
        spark.read
        .option("header", True)
        .option("inferSchema", True)
        .csv(str(path))
    )


def write_summary(df, folder_name):
    output_path = OUTPUT_DIR / folder_name
    (
        df.coalesce(1)
        .write
        .mode("overwrite")
        .option("header", True)
        .csv(str(output_path))
    )
    print(f"Created {output_path}")


def build_branch_revenue_summary(payments):
    if payments is None:
        return

    summary = (
        payments.groupBy("branch_name")
        .agg(
            count("order_id").alias("paid_orders"),
            spark_sum("amount_paid").alias("total_revenue"),
            avg("amount_paid").alias("avg_payment"),
        )
        .orderBy(desc("total_revenue"), desc("paid_orders"))
    )

    write_summary(summary, "branch_revenue_summary")


def build_payment_method_summary(payments):
    if payments is None:
        return

    summary = (
        payments.groupBy("payment_method")
        .agg(
            count("payment_id").alias("payment_count"),
            spark_sum("amount_paid").alias("total_amount"),
            avg("amount_paid").alias("avg_amount"),
        )
        .orderBy(desc("total_amount"))
    )

    write_summary(summary, "payment_method_summary")


def build_menu_sales_summary(order_items):
    if order_items is None:
        return

    summary = (
        order_items.groupBy("item_name", "category_name")
        .agg(
            spark_sum("quantity").alias("quantity_sold"),
            spark_sum("line_total").alias("gross_sales"),
            avg("agreed_unit_price").alias("avg_unit_price"),
        )
        .orderBy(desc("quantity_sold"), desc("gross_sales"))
    )

    write_summary(summary, "menu_sales_summary")


def build_reservation_status_summary(reservations):
    if reservations is None:
        return

    summary = (
        reservations.groupBy("branch_name", "reservation_status")
        .agg(count("reservation_id").alias("reservation_count"))
        .orderBy("branch_name", desc("reservation_count"))
    )

    write_summary(summary, "reservation_status_summary")


def build_feedback_summary(feedback):
    if feedback is None:
        return

    summary = (
        feedback.groupBy("branch_name")
        .agg(
            count("feedback_id").alias("feedback_count"),
            avg("rating").alias("avg_rating"),
        )
        .orderBy(desc("avg_rating"), desc("feedback_count"))
    )

    write_summary(summary, "feedback_summary")


def main():
    parser = argparse.ArgumentParser(
        description="Create PySpark summary CSV folders from restaurant export CSV files."
    )
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=DEFAULT_SOURCE_DIR,
        help="Folder containing CSV exports from the Flask analytics page.",
    )
    args = parser.parse_args()

    source_dir = args.source_dir.expanduser().resolve()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    spark = create_spark_session()

    try:
        payments = read_csv_if_exists(spark, source_dir, "payments_export.csv")
        order_items = read_csv_if_exists(spark, source_dir, "order_items_export.csv")
        reservations = read_csv_if_exists(spark, source_dir, "reservations_export.csv")
        feedback = read_csv_if_exists(spark, source_dir, "feedback_export.csv")

        build_branch_revenue_summary(payments)
        build_payment_method_summary(payments)
        build_menu_sales_summary(order_items)
        build_reservation_status_summary(reservations)
        build_feedback_summary(feedback)
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
